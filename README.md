# EKS + ArgoCD: step-by-step for beginners

తెలుగులో వివరణ కోసం [README.te.md](README.te.md) చూడండి.

By the end you will have, in your own AWS account:
- an **EKS cluster** (Kubernetes on AWS), built by **Terraform**
- **ArgoCD** installed on it
- a small web app **deployed by ArgoCD from your own GitHub repo**
- a **GitHub Action** that does all of this when you run it (it logs in to AWS with an access key stored as a GitHub secret)

## How it fits together

```
you push to GitHub ──> GitHub Action ──> Terraform builds EKS + installs ArgoCD
                                    └──> tells ArgoCD "watch the app/ folder of my repo"
ArgoCD (in the cluster) ──> reads app/ from GitHub ──> runs your app
```

After the first run, changing a file in `app/` and pushing is enough. ArgoCD notices and updates the app. No pipeline needed for that part.

## What is in this folder

| Path | What it is |
|---|---|
| `terraform/` | Code that creates the network, the EKS cluster and installs ArgoCD |
| `app/app.yaml` | The app itself (a tiny nginx web page) that ArgoCD deploys |
| `argocd/app.yaml` | Tells ArgoCD where your app lives (your repo, folder `app`) |
| `.github/workflows/deploy.yaml` | The GitHub Action |

## Before you start: cost warning
EKS costs roughly **$5-6 per day** while it exists. Do Step 8 (destroy) when you finish. Use a personal or training AWS account, not a work one.

## Step 0: Install the tools on your computer
You need: `git`, the [GitHub CLI](https://cli.github.com) (`gh`), the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), and `kubectl`.

Check they work:
```bash
git --version && gh --version && aws --version && kubectl version --client
```

## Step 1: Log in to AWS from your terminal
```bash
aws configure          # paste your access key, secret, and a region like ap-south-1
aws sts get-caller-identity   # should print your account ID
```

## Step 2: Create your own GitHub repository
**It must be a public repo** so ArgoCD can read it without a password (fine for learning; never put secrets in it).

```bash
gh auth login                       # follow the prompts once
cd eks-argocd-starter               # this folder
git init -b main
git add .
git commit -m "Initial EKS + ArgoCD starter"
gh repo create eks-argocd-demo --public --source=. --push
```
No `gh`? Create an empty public repo on github.com instead, then:
```bash
git remote add origin https://github.com/<your-user>/eks-argocd-demo.git
git push -u origin main
```
The first push may trigger the Action, and it will **fail** because AWS isn't set up yet. That's expected. Do Step 3 and 4, then start a new run.

## Step 3: Create a bucket for Terraform's memory (state)
Terraform must remember what it built. The Action runs on a fresh machine every time, so the state lives in an S3 bucket. Run this once with your own AWS login from Step 1:

```bash
REGION=ap-south-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET=tfstate-$ACCOUNT_ID-$REGION

aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"   # in us-east-1 leave this line out
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
echo "$BUCKET"
```
Keep the bucket name for Step 4.

## Step 4: Give GitHub the AWS login and settings
The Action logs in to AWS with an **access key** of an IAM user that is allowed to create a VPC, an EKS cluster and IAM roles (for learning, `AdministratorAccess`; never do this in a real account). Create a **new** access key for it (IAM > Users > your user > Security credentials), and use it only for this demo.

On github.com open your repo, then **Settings > Secrets and variables > Actions**, or use the CLI (it asks for each value; **never paste keys into chat, code or commits**):

```bash
gh secret set AWS_ACCESS_KEY_ID
gh secret set AWS_SECRET_ACCESS_KEY
gh variable set AWS_REGION --body "ap-south-1"
gh variable set TF_STATE_BUCKET --body "<bucket from Step 3>"
```
Set them as **repository** secrets and variables. The workflow job also uses an environment named `variables` (`environment: variables` in `deploy.yaml`), which GitHub creates automatically. Variables defined only inside a *different* environment are not visible to the job and show up empty.

**Security:** these keys stay valid until you delete them, and anyone who can edit the workflow can read them. Delete the key in AWS (IAM > Security credentials > Delete) and the two secrets in GitHub as soon as you finish (Step 8). The safer pattern for real projects is OpenID Connect (OIDC): GitHub proves its identity to AWS and gets temporary credentials, so no long-lived key is stored. See "Safer alternative" at the end.

## Step 5: Run the Action to build everything
Repo > **Actions** tab > *EKS + ArgoCD* > **Run workflow** > choose `apply` > Run.

It takes about 15-20 minutes. Green check = done. If it fails, open the failed step and read the error (see Troubleshooting below).

## Step 6: Look at ArgoCD and your app
```bash
aws eks update-kubeconfig --name demo-eks --region ap-south-1
kubectl get nodes                      # 2 nodes in Ready state (see "You must be logged in" below if this fails)
kubectl -n argocd get applications     # my-app should be Synced / Healthy
kubectl -n my-app get pods             # 2 hello pods Running
```

Open your app:
```bash
kubectl -n my-app port-forward svc/hello 8081:80
# browse to http://localhost:8081
```

Open the ArgoCD web page (in a second terminal):
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443
# browse to https://localhost:8080  (accept the browser warning)  user: admin
```

## Step 7: Make a change and watch ArgoCD deploy it
Edit `app/app.yaml`, change "version 1" to "version 2", then:
```bash
git commit -am "Change message" && git push
```
Within about 3 minutes ArgoCD syncs it (click *Refresh* in the UI to speed it up). Reload `http://localhost:8081` to see the change. You changed Git and the cluster followed. This is GitOps.

## Step 8: Delete everything (stop the charges)
1. Repo > Actions > *EKS + ArgoCD* > Run workflow > choose `destroy`. Wait for the green check.
2. Then delete the state bucket if you're finished for good (empty it first, including old versions).
3. **Delete the access key** in AWS (IAM > Users > Security credentials), and the `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` secrets in GitHub:
   ```bash
   gh secret delete AWS_ACCESS_KEY_ID
   gh secret delete AWS_SECRET_ACCESS_KEY
   ```
   Deleting only the GitHub secret is not enough, because the key stays valid in AWS.

## Troubleshooting
- **"Input required and not supplied: aws-region":** `AWS_REGION` is empty in the job. Define it as a repository variable (Step 4), or in the `variables` environment the job uses. Then start a **new** run with *Run workflow*, because "Re-run" reuses the old commit.
- **"Credentials could not be loaded" / "InvalidClientTokenId" / "SignatureDoesNotMatch":** `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` is missing, mistyped, or the key was deleted or made inactive.
- **`AccessDenied` during plan/apply:** the IAM user behind the key lacks permissions for EKS, VPC, EC2 or IAM.
- **`kubectl`: "You must be logged in to the server":** the cluster creator is the IAM user whose key the Action uses. If you run `kubectl` as someone else, give that identity access:
  ```bash
  ME=$(aws sts get-caller-identity --query Arn --output text)
  aws eks create-access-entry --cluster-name demo-eks --region ap-south-1 --principal-arn "$ME"
  aws eks associate-access-policy --cluster-name demo-eks --region ap-south-1 --principal-arn "$ME" \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster
  ```
  (For a role, use the role ARN, not the assumed-role ARN from `get-caller-identity`.)
- **Backend / bucket error:** check the `TF_STATE_BUCKET` and `AWS_REGION` variables, and that the bucket is in that region.
- **ArgoCD app shows "Unknown" or can't read the repo:** make sure the repo is public.
- **Destroy fails on VPC:** run destroy again. Leftover load balancers take a few minutes to go away.
- **Quota errors for NAT gateway / Elastic IP:** pick another region (set `AWS_REGION` and create the bucket there).

## Next steps once this works
Add your own app (a Helm chart or more YAML in `app/`), then add an Ingress or LoadBalancer Service so it's reachable without port-forward, then split into separate repos (infra repo and app repo), which is how teams usually do it.

## Safer alternative: OIDC instead of access keys
Instead of storing a key, GitHub can sign a short-lived identity token and AWS can exchange it for temporary credentials. You create, once, an IAM OIDC provider for `token.actions.githubusercontent.com` and an IAM role whose trust policy only allows your repo, then use `role-to-assume: ${{ secrets.AWS_ROLE_ARN }}` in `deploy.yaml` instead of the two key inputs (the job already has `permissions: id-token: write`). Watch the role's trust policy: GitHub's `sub` claim can come as `repo:<user>/<repo>:...` or `repo:<user>@<owner-id>/<repo>@<repo-id>:...`, so allow both forms. This repo's history shows that setup.
