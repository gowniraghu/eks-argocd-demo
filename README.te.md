# eks-argocd-demo: తెలుగులో వివరణ

ఇది [README.md](README.md) లోని ప్రతి step లో నిజంగా ఏం జరుగుతుందో తెలుగులో వివరిస్తుంది.

## మొత్తం చిత్రం

```
మీరు GitHub కి push చేస్తారు
   └─> GitHub Action (deploy.yaml) నడుస్తుంది
         ├─> AWS లో లాగిన్ అవుతుంది (GitHub secret లోని access key తో)
         ├─> Terraform: VPC + EKS cluster + ArgoCD తయారు చేస్తుంది
         └─> ArgoCD కి చెబుతుంది: "నా repo లోని app/ folder ని చూస్తూ ఉండు"
ArgoCD (cluster లోపల) ──> GitHub నుండి app/ చదివి ──> app ని నడుపుతుంది
```

రెండు వేర్వేరు పనులు ఉన్నాయి:
- **Infrastructure** (cluster, network): Terraform తయారు చేస్తుంది.
- **Application** (nginx web page): ArgoCD నడుపుతుంది.

## Step 0: tools install చేయడం

`git`, `gh`, `aws`, `kubectl` కావాలి.
- `git`: code ని push చేయడానికి.
- `gh`: GitHub లో repo, secrets, variables తయారు చేయడానికి.
- `aws`: AWS తో మాట్లాడటానికి.
- `kubectl`: cluster తో మాట్లాడటానికి.

ఈ step లో ఏదీ తయారవదు. tools ఉన్నాయో లేదో మాత్రమే చూస్తుంది.

## Step 1: AWS కి లాగిన్ (మీ కంప్యూటర్ నుండి)

`aws configure` లో access key, secret, region ఇస్తారు. అవి `~/.aws/credentials` లో save అవుతాయి. `aws sts get-caller-identity` అనేది "నేను ఎవరు?" అని AWS ని అడుగుతుంది. account ID చూపిస్తే లాగిన్ సరిగ్గా ఉన్నట్టు.

**ఎందుకు కావాలి:** Step 3 లో మీరు AWS లో bucket తయారు చేయాలి. దానికి మీ credentials కావాలి. ఇవి **మీ కంప్యూటర్ కోసం** మాత్రమే. GitHub Action కోసం Step 4 లో వేరే key పెడతారు.

## Step 2: మీ GitHub repo తయారు చేయడం

`gh repo create eks-argocd-demo --public --source=. --push` ఈ folder ని GitHub కి పంపుతుంది.

**Repo public ఎందుకు:** ArgoCD cluster లోపల నుండి GitHub లోని `app/` folder ని చదవాలి. Private అయితే password ఇవ్వాలి. Public అయితే అవసరం లేదు. నేర్చుకోవడానికి సరే, కానీ secrets ఎప్పుడూ పెట్టకూడదు.

**మొదటి push తర్వాత Action fail అవుతుంది.** ఎందుకంటే AWS role, variables ఇంకా లేవు. అది ఊహించిందే.

## Step 3: Terraform state కోసం S3 bucket

Terraform "నేను ఏం తయారు చేశాను" అని **state file** లో గుర్తుంచుకుంటుంది. GitHub Action ప్రతిసారి కొత్త machine లో నడుస్తుంది కాబట్టి state బయట ఉండాలి. లేకపోతే Terraform అన్నీ మళ్ళీ కొత్తగా తయారు చేయడానికి ప్రయత్నిస్తుంది. README లోని ఈ కమాండ్లను మీ కంప్యూటర్ లో ఒకసారి నడపండి:

```bash
REGION=ap-south-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET=tfstate-$ACCOUNT_ID-$REGION
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
```

Versioning ఆన్ చేస్తే, పొరపాటున state పాడైతే వెనక్కి వెళ్ళవచ్చు. Bucket పేరు Step 4 కి కావాలి.

## GitHub, AWS కి ఎలా లాగిన్ అవుతుంది (access keys)

ఈ demo లో GitHub Action, AWS లోని ఒక **IAM user యొక్క access key** తో లాగిన్ అవుతుంది. ఆ key GitHub **secrets** లో ఉంటుంది:

```
GitHub Action ── AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY (secrets నుండి) ──> AWS
```

- `aws-actions/configure-aws-credentials` ఆ keys ని తీసుకుని, Action నడుస్తున్న machine లో AWS లాగిన్ ఏర్పాటు చేస్తుంది. Terraform ఆ లాగిన్ తో పని చేస్తుంది.
- ఆ user కి VPC, EKS, IAM తయారు చేసే అనుమతులు ఉండాలి. నేర్చుకోవడానికి `AdministratorAccess` ఇస్తారు. నిజమైన account లో ఇలా చేయకూడదు.
- EKS cluster ని తయారు చేసినవారే cluster admin. అంటే ఇక్కడ ఆ IAM user. అందుకే అదే user తో `kubectl` వాడితే access ఉంటుంది.

**ప్రమాదాలు:**
- Keys మీరు తొలగించే వరకు చెల్లుతాయి.
- Workflow ని మార్చగలిగే ఎవరైనా ఆ keys ని చదివి బయటకు పంపవచ్చు.
- Keys ని chat లో, కోడ్ లో, commit లో ఎక్కడా పెట్టవద్దు. `gh secret set` వాడండి.
- **పని ముగిశాక** AWS లో key ని తొలగించండి, GitHub secrets కూడా తొలగించండి (Step 8).

**ఈ demo కోసం విడిగా కొత్త access key తయారు చేయండి** (IAM → Users → Security credentials). ఆ user ఇతర పనులకు కూడా వాడబడుతుంటే, key తొలగించడం వల్ల అవి ఆగకుండా ఉంటుంది.

## Step 4: GitHub కి keys, సెట్టింగ్స్ ఇవ్వడం

మీ టెర్మినల్ లో (విలువ అడిగినప్పుడు టైప్ చేయండి):
```bash
gh secret set AWS_ACCESS_KEY_ID
gh secret set AWS_SECRET_ACCESS_KEY
gh variable set AWS_REGION --body "ap-south-1"
gh variable set TF_STATE_BUCKET --body "<Step 3 లోని bucket పేరు>"
```

| విలువ | ఎక్కడ వాడతారు | లేకపోతే |
|---|---|---|
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (secrets) | AWS లాగిన్ | `Credentials could not be loaded` |
| `AWS_REGION` (variable) | `aws-region:`, `-var=region`, kubeconfig | `Input required: aws-region` |
| `TF_STATE_BUCKET` (variable) | `terraform init -backend-config` | state ఎక్కడ ఉందో తెలియదు |

- **Region, bucket రహస్యాలు కావు**, అందుకే అవి Variables. Keys మాత్రమే Secrets (logs లో `***` గా కనిపిస్తాయి).
- **Environment గురించి:** Variables ని ఒక environment లో మాత్రమే పెడితే, job కి `environment:` ఉంటేనే కనిపిస్తాయి. Workflow లో `environment: variables` ఉంది. Repository స్థాయిలో పెడితే అన్నిచోట్లా కనిపిస్తాయి.

## Step 5: Action నడపడం (`deploy.yaml`)

*Actions → Run workflow → apply.* క్రమం:

1. **checkout:** repo code ని machine లోకి తెస్తుంది.
2. **configure-aws-credentials:** secrets లోని keys తో AWS లాగిన్ ఏర్పాటు చేస్తుంది.
3. **setup-terraform:** Terraform install చేస్తుంది.
4. **`terraform init`:** state ఎక్కడ ఉందో (S3 bucket) చెబుతుంది, providers ని download చేస్తుంది.
5. **`terraform fmt -check`:** formatting సరిగ్గా ఉందా చూస్తుంది. లేకపోతే fail.
6. **`terraform validate`:** syntax తప్పులు చూస్తుంది.
7. **`terraform plan`:** ఏం తయారవుతుందో చూపిస్తుంది. Pull request లో ఇది మాత్రమే నడుస్తుంది.
8. **`terraform apply`:** నిజంగా తయారు చేస్తుంది. `main` కి push అయినప్పుడు, లేదా manual `apply` ఎంచుకున్నప్పుడు మాత్రమే.
9. **Deploy app through ArgoCD:** `argocd/app.yaml` ని `kubectl apply` చేస్తుంది. `REPO_URL_PLACEHOLDER` ని మీ repo URL తో మారుస్తుంది.

**Terraform తయారు చేసేవి** (`terraform/main.tf`):
- **VPC:** 2 public + 2 private subnets, ఒకే NAT gateway (చవక).
- **EKS cluster:** Kubernetes 1.31, 2 nodes (`t3.medium`). `enable_cluster_creator_admin_permissions = true` వల్ల cluster ని తయారు చేసిన GitHub role మాత్రమే admin. అంటే Action లోని IAM user cluster admin. వేరే identity తో `kubectl` వాడాలంటే access entry చేర్చాలి (README troubleshooting చూడండి).
- **ArgoCD:** Helm chart తో cluster లో install అవుతుంది.

ఇది 15–20 నిమిషాలు పడుతుంది. EKS cluster తయారవడమే అంత సమయం తీసుకుంటుంది.

## Step 6: ArgoCD, app చూడటం

`aws eks update-kubeconfig` మీ `kubectl` కి cluster చిరునామా, లాగిన్ పద్ధతి ఇస్తుంది. తర్వాత:
- `kubectl get nodes`: 2 nodes Ready గా ఉండాలి.
- `kubectl -n argocd get applications`: `my-app` Synced/Healthy గా ఉండాలి.
- `kubectl -n my-app get pods`: 2 `hello` pods నడుస్తూ ఉండాలి.

**Port-forward ఎందుకు:** Service ClusterIP, అంటే లోపలి చిరునామా మాత్రమే. బయటి నుండి లింక్ లేదు. `port-forward` మీ కంప్యూటర్ నుండి cluster లోని service కి తాత్కాలిక సొరంగం తవ్వుతుంది. కమాండ్ నడుస్తున్నంత వరకే పనిచేస్తుంది.

**ArgoCD password:** ArgoCD మొదటిసారి install అయినప్పుడు `argocd-initial-admin-secret` అనే secret లో random password పెడుతుంది. దాన్ని base64 నుండి decode చేసి చూపిస్తాం. Username `admin`.

## Step 7: మార్పు చేసి GitOps చూడటం

`app/app.yaml` లో "version 1" ని "version 2" చేసి push చేస్తారు. ఇక్కడ **Action నడవదు**, ఎందుకంటే workflow `terraform/**`, `argocd/**` మార్పులకే trigger అవుతుంది. బదులుగా:
1. ArgoCD ప్రతి ~3 నిమిషాలకు మీ repo లోని `app/` ని చూస్తుంది.
2. Git లో ఉన్నదానికీ cluster లో ఉన్నదానికీ తేడా కనిపిస్తే మార్చుకుంటుంది (`automated: prune, selfHeal`).
3. `selfHeal` వల్ల ఎవరైనా `kubectl` తో చేత్తో మార్చినా, ArgoCD Git లో ఉన్న రూపానికే తిరిగి మారుస్తుంది.

దీన్నే **GitOps** అంటారు: Git లో ఉన్నదే నిజం, cluster దాన్ని అనుసరిస్తుంది.

## Step 8: అన్నీ తొలగించడం (destroy)

1. *Run workflow → destroy.* Workflow ముందు ArgoCD app ని తొలగిస్తుంది (లేకపోతే app తయారు చేసిన load balancers, volumes AWS లో మిగిలిపోయి VPC తొలగడం ఆగిపోతుంది), తర్వాత `terraform destroy` తో cluster, VPC, NAT అన్నీ తొలగిస్తుంది. Green check వచ్చే వరకు ఆగండి.
2. పూర్తిగా ముగించేస్తే S3 bucket ని కూడా తొలగించండి. అది destroy లో తొలగదు, మీరు చేత్తో తయారు చేశారు. ముందు bucket ను (పాత versions తో సహా) ఖాళీ చేయాలి. State bucket ని cluster తొలగిన **తర్వాత** మాత్రమే తొలగించండి.
3. **AWS లో access key ని తొలగించండి**, తర్వాత GitHub secrets:
   ```bash
   gh secret delete AWS_ACCESS_KEY_ID
   gh secret delete AWS_SECRET_ACCESS_KEY
   ```
   GitHub secret మాత్రమే తొలగిస్తే సరిపోదు. AWS లో key ఇంకా చెల్లుతుంది.

## సాధారణ errors

| Error | కారణం | పరిష్కారం |
|---|---|---|
| `aws-region` not supplied | `AWS_REGION` variable లేదు లేదా వేరే environment లో ఉంది | Repository variable పెట్టండి, లేదా job లో `environment:` వాడండి |
| Credentials could not be loaded / InvalidClientTokenId / SignatureDoesNotMatch | Keys లేవు, తప్పుగా టైప్ చేశారు, లేదా key తొలగించారు/Inactive చేశారు | Secrets ని సరిచేయండి |
| AccessDenied (plan/apply లో) | Key యొక్క IAM user కి EKS, VPC, EC2, IAM అనుమతులు లేవు | అనుమతులు ఇవ్వండి |
| kubectl: must be logged in | Cluster తయారు చేసిన user కాకుండా వేరే identity వాడుతున్నారు | ఆ identity కి access entry ఇవ్వండి (README) |
| Backend / bucket error | `TF_STATE_BUCKET` లేదా region తప్పు | Variables, bucket region చూడండి |

## సురక్షితమైన ప్రత్యామ్నాయం: OIDC

Keys నిల్వ చేయడానికి బదులు OIDC వాడవచ్చు. GitHub ఒక తాత్కాలిక గుర్తింపు token ఇస్తుంది, AWS దాన్ని ధృవీకరించి తాత్కాలిక credentials ఇస్తుంది, కాబట్టి దీర్ఘకాలం చెల్లే key ఎక్కడా ఉండదు. దీనికి AWS లో OIDC provider, మీ repo కి మాత్రమే అనుమతించే trust policy ఉన్న IAM role కావాలి, మరియు `deploy.yaml` లో keys బదులు `role-to-assume` వాడాలి. Trust policy లో GitHub `sub` రెండు రూపాల్లో రావచ్చు (పేరు రూపం, లేదా `owner@id/repo@id` ID రూపం), రెండింటినీ అనుమతించండి. నిజమైన ప్రాజెక్టులకు ఇదే సిఫార్సు.

Fix తర్వాత "Re-run" వాడకండి. అది పాత commit నే వాడుతుంది. *Run workflow* తో కొత్త run మొదలుపెట్టండి.
