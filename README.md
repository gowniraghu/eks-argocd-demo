# EKS + ArgoCD: step-by-step for beginners

తెలుగులో వివరణ కోసం [README.te.md](README.te.md) చూడండి.

By the end you will have, in your own AWS account:
- an **EKS cluster** (Kubernetes on AWS), built by **Terraform**
- **ArgoCD** installed on it
- a small web app **deployed by ArgoCD from your own GitHub repo**
- a **GitHub Action** that does all of this when you push code

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
| `scripts/setup-aws.sh` | One-time AWS setup so GitHub can log in to AWS |

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
The first push triggers the Action, and it will **fail** because AWS isn't set up yet. That's expected. Do Step 3 and 4, then re-run it.

## Step 3: One-time AWS setup (lets GitHub log in to AWS)
This creates a bucket for Terraform's memory (state), and an IAM role that only your repo can use.

```bash
./scripts/setup-aws.sh <your-github-user> eks-argocd-demo ap-south-1
```
At the end it prints three values. Keep them for Step 4.

The script looks up your repo's numeric IDs from the GitHub API (the repo must be public) and trusts both forms of GitHub's login identity, `repo:<user>/<repo>` and `repo:<user>@<owner-id>/<repo>@<repo-id>`. GitHub can send the second form, and a role that trusts only the first one rejects the login.

(The role gets `AdministratorAccess` to keep learning simple. Don't do this in a real account.)

## Step 4: Give GitHub those three values
On github.com open your repo, then **Settings > Secrets and variables > Actions**:

1. **Secrets** tab > *New repository secret*: name `AWS_ROLE_ARN`, value from the script.
2. **Variables** tab > *New repository variable* twice: `AWS_REGION` and `TF_STATE_BUCKET`, with the values from the script.

Or with the CLI:
```bash
gh secret set AWS_ROLE_ARN --body "arn:aws:iam::<account>:role/github-actions-eks-demo"
gh variable set AWS_REGION --body "ap-south-1"
gh variable set TF_STATE_BUCKET --body "<bucket from script>"
```
Set them as **repository** secrets and variables. The workflow job also uses an environment named `variables` (`environment: variables` in `deploy.yaml`), which GitHub creates automatically. Variables and secrets defined only inside a *different* environment are not visible to the job and show up as empty values.

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
Repo > Actions > *EKS + ArgoCD* > Run workflow > choose `destroy`.

Afterwards, in AWS, you can also delete the state bucket and the `github-actions-eks-demo` role if you're finished for good. If you skip them they cost almost nothing.

## Troubleshooting
- **"Could not assume role" / "not authorized to perform sts:AssumeRoleWithWebIdentity":** the repo name in Step 3 must match your GitHub `user/repo` exactly, `AWS_ROLE_ARN` must be set, and the role's trust policy must allow your repo's login identity (including the ID form, see Step 3). CloudTrail's `AssumeRoleWithWebIdentity` event shows the exact identity GitHub sent.
- **"Input required and not supplied: aws-region" or "Could not load credentials":** `AWS_REGION` or `AWS_ROLE_ARN` is empty in the job. Define them as repository secrets and variables (Step 4), or in the `variables` environment the job uses. Then start a **new** run with *Run workflow*, because "Re-run" reuses the old commit.
- **`kubectl`: "You must be logged in to the server":** only the GitHub Actions role is cluster admin, because it created the cluster. Give your own IAM user access:
  ```bash
  ME=$(aws sts get-caller-identity --query Arn --output text)
  aws eks create-access-entry --cluster-name demo-eks --region ap-south-1 --principal-arn "$ME"
  aws eks associate-access-policy --cluster-name demo-eks --region ap-south-1 --principal-arn "$ME" \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster
  ```
  (For a role, use the role ARN, not the assumed-role ARN from `get-caller-identity`.)
- **Backend / bucket error:** check the `TF_STATE_BUCKET` and `AWS_REGION` variables.
- **ArgoCD app shows "Unknown" or can't read the repo:** make sure the repo is public.
- **Destroy fails on VPC:** run destroy again. Leftover load balancers take a few minutes to go away.
- **Quota errors for NAT gateway / Elastic IP:** pick another region in Step 3.

## Next steps once this works
Add your own app (a Helm chart or more YAML in `app/`), then add an Ingress or LoadBalancer Service so it's reachable without port-forward, then split into separate repos (infra repo and app repo), which is how teams usually do it.
