# eks-argocd-demo: తెలుగులో వివరణ

ఇది [README.md](README.md) లోని ప్రతి step లో నిజంగా ఏం జరుగుతుందో తెలుగులో వివరిస్తుంది.

## మొత్తం చిత్రం

```
మీరు GitHub కి push చేస్తారు
   └─> GitHub Action (deploy.yaml) నడుస్తుంది
         ├─> AWS లో లాగిన్ అవుతుంది (OIDC, passwords లేకుండా)
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

**ఎందుకు కావాలి:** Step 3 లో script AWS లో bucket, role తయారు చేయాలి. దానికి మీ credentials కావాలి. ఇవి **మీ కంప్యూటర్ కోసం** మాత్రమే. GitHub Action ఈ keys ని వాడదు.

## Step 2: మీ GitHub repo తయారు చేయడం

`gh repo create eks-argocd-demo --public --source=. --push` ఈ folder ని GitHub కి పంపుతుంది.

**Repo public ఎందుకు:** ArgoCD cluster లోపల నుండి GitHub లోని `app/` folder ని చదవాలి. Private అయితే password ఇవ్వాలి. Public అయితే అవసరం లేదు. నేర్చుకోవడానికి సరే, కానీ secrets ఎప్పుడూ పెట్టకూడదు.

**మొదటి push తర్వాత Action fail అవుతుంది.** ఎందుకంటే AWS role, variables ఇంకా లేవు. అది ఊహించిందే.

## Step 3: AWS setup (`scripts/setup-aws.sh`)

ఈ script మూడు పనులు చేస్తుంది. మీ కంప్యూటర్ లోని AWS credentials తో ఒకసారి నడుస్తుంది.

**(1) S3 bucket:** `tfstate-<account>-<region>` అనే bucket. Terraform "నేను ఏం తయారు చేశాను" అని గుర్తుంచుకునే **state file** ఇందులో ఉంటుంది. GitHub Action ప్రతిసారి కొత్త machine లో నడుస్తుంది కాబట్టి state బయట ఉండాలి. లేకపోతే Terraform అన్నీ మళ్ళీ కొత్తగా తయారు చేయడానికి ప్రయత్నిస్తుంది. Versioning ఆన్ చేస్తారు, పొరపాటున state పాడైతే వెనక్కి వెళ్ళవచ్చు.

**(2) OIDC provider:** AWS కి "GitHub ని నమ్ము" అని చెప్పే సెట్టింగ్. ఇది ఉంటే GitHub Action AWS keys లేకుండా లాగిన్ అవుతుంది. Keys ని GitHub లో దాచి ఉంచే అవసరం ఉండదు, leak అయ్యే ప్రమాదం ఉండదు.

**(3) IAM role `github-actions-eks-demo`:** GitHub Action తీసుకునే role. దీని **trust policy** ఇలా అంటుంది: "GitHub నుండి వచ్చిన token లో `aud = sts.amazonaws.com` ఉండి, `sub` నా repo కి చెందినదైతే మాత్రమే ఈ role ఇవ్వు".

GitHub పంపే `sub` రెండు రూపాల్లో ఉండవచ్చు: `repo:<user>/<repo>:...` లేదా ID లతో `repo:<user>@<owner-id>/<repo>@<repo-id>:...`. Policy లో పేరు రూపం మాత్రమే ఉంటే role reject అవుతుంది. అందుకే script రెండు రూపాలనూ అనుమతిస్తుంది.

Role కి `AdministratorAccess` ఇచ్చాం, ఎందుకంటే VPC, EKS, IAM అన్నీ తయారు చేయాలి. నేర్చుకోవడానికి సరే, నిజమైన account లో కాదు.

చివరికి script మూడు విలువలు ప్రింట్ చేస్తుంది: role ARN, region, bucket పేరు.

## GitHub, AWS కి keys లేకుండా ఎలా లాగిన్ అవుతుంది

GitHub లో మీరు పెట్టేవి: `AWS_ROLE_ARN` (ఏ role అనే చిరునామా మాత్రమే), `AWS_REGION`, `TF_STATE_BUCKET`. **password, access key, secret key ఏదీ లేదు.**

**ఆలోచన:** రెండు పార్టీల మధ్య password పంచుకోవడానికి బదులు, ఇద్దరూ నమ్మే ఒక గుర్తింపు పద్ధతిని వాడతారు. ఒక పోలిక: ఆఫీసు గేటు దగ్గర గార్డు (AWS) ఉంటాడు. ముందే ఇలా నిర్ణయించుకున్నాడు: "ఈ ప్రభుత్వం (GitHub) జారీ చేసిన ID, ఈ repo పేరు ఉన్నవారికి మాత్రమే లోపలికి అనుమతి". Step 3 ఈ సూచనలను ముందే ఇవ్వడం.

**ప్రతి run లో జరిగేది:**

```
 GitHub Action                    GitHub                         AWS
      │── "నాకు token కావాలి" ───────>│                            │
 1.   │<── JWT token (signed) ────────│                            │
 2.   │── token + role ARN ─────────────────────────────────────>│
 3.   │                                         signature, aud, sub తనిఖీ
 4.   │<──────────── తాత్కాలిక keys (≈1 గంట) ────────────────────│
 5.   │── ఆ keys తో terraform, aws commands ───────────────────>│
```

1. **Token:** Workflow లో `permissions: id-token: write` ఉంటే GitHub ఒక JWT token ఇస్తుంది. అందులో claims ఉంటాయి: `iss` (జారీ చేసినవారు), `aud` (ఎవరి కోసం), `sub` (ఎవరు: repo, branch, environment). GitHub తన private key తో దీనిపై signature వేస్తుంది.
2. **AWS కి పంపడం:** Action token ని AWS కి పంపి, ఏ role కావాలో చెబుతుంది.
3. **తనిఖీ:** AWS, GitHub public keys తో signature ని చూస్తుంది, తర్వాత `aud`, `sub` ని trust policy తో పోలుస్తుంది.
4. **తాత్కాలిక keys:** సరిపోతే AWS సుమారు 1 గంటలో చెల్లని credentials ఇస్తుంది.
5. **పని:** Terraform ఆ keys తో పని చేస్తుంది.

| | access keys | OIDC |
|---|---|---|
| **GitHub లో నిల్వ** | దీర్ఘకాలం చెల్లే keys | ఏ రహస్యమూ లేదు |
| **leak అయితే** | రద్దు చేసే వరకు ఎవరైనా వాడవచ్చు | కొద్ది సమయంలో చెల్లదు |
| **ఎవరు వాడగలరు** | keys ఉన్న ఎవరైనా | trust policy లోని repo మాత్రమే |

**హెచ్చరిక:** Trust policy `repo:...:*` అంటే ఆ repo లోని ఏ branch, ఏ workflow అయినా role తీసుకోగలదు, మరియు role కి Admin ఉంది. నిజమైన account లో `environment`, workflow పేరు, branch తో పరిమితం చేయాలి.

## Step 4: GitHub కి ఆ విలువలు ఇవ్వడం (OIDC ఉన్నా ఎందుకు)

OIDC provider "ఈ token ని నమ్ము" అని మాత్రమే చెబుతుంది. అది workflow కి ఇవి చెప్పదు: ఏ role, ఏ region, ఏ bucket. అవి సెట్టింగ్స్, passwords కావు.

| విలువ | ఎక్కడ వాడతారు | లేకపోతే |
|---|---|---|
| `AWS_ROLE_ARN` (secret) | `role-to-assume:` | `Could not load credentials` |
| `AWS_REGION` (variable) | `aws-region:`, `-var=region`, kubeconfig | `Input required: aws-region` |
| `TF_STATE_BUCKET` (variable) | `terraform init -backend-config` | state ఎక్కడ ఉందో తెలియదు |

- **తాళం చెవి vs చిరునామా:** access key తాళం చెవి, దాచాలి. Role ARN చిరునామా మాత్రమే. తెలిసినా గార్డు (trust policy) ID చూసి మాత్రమే లోపలికి పంపుతాడు.
- **YAML లో నేరుగా ఎందుకు రాయం:** రాయవచ్చు. కానీ repo public, ARN లో account ID ఉంటుంది. Secret అయితే logs లో `***` గా కనిపిస్తుంది. ఇతరులు repo ని copy చేసుకుని తమ విలువలు పెట్టుకోవచ్చు.
- **Environment గురించి:** Variables ని ఒక environment లో మాత్రమే పెడితే, job కి `environment:` ఉంటేనే కనిపిస్తాయి. Workflow లో `environment: variables` ఉంది.

## Step 5: Action నడపడం (`deploy.yaml`)

*Actions → Run workflow → apply.* క్రమం:

1. **checkout:** repo code ని machine లోకి తెస్తుంది.
2. **configure-aws-credentials:** పైన వివరించిన OIDC ద్వారా తాత్కాలిక keys తీసుకుంటుంది.
3. **setup-terraform:** Terraform install చేస్తుంది.
4. **`terraform init`:** state ఎక్కడ ఉందో (S3 bucket) చెబుతుంది, providers ని download చేస్తుంది.
5. **`terraform fmt -check`:** formatting సరిగ్గా ఉందా చూస్తుంది. లేకపోతే fail.
6. **`terraform validate`:** syntax తప్పులు చూస్తుంది.
7. **`terraform plan`:** ఏం తయారవుతుందో చూపిస్తుంది. Pull request లో ఇది మాత్రమే నడుస్తుంది.
8. **`terraform apply`:** నిజంగా తయారు చేస్తుంది. `main` కి push అయినప్పుడు, లేదా manual `apply` ఎంచుకున్నప్పుడు మాత్రమే.
9. **Deploy app through ArgoCD:** `argocd/app.yaml` ని `kubectl apply` చేస్తుంది. `REPO_URL_PLACEHOLDER` ని మీ repo URL తో మారుస్తుంది.

**Terraform తయారు చేసేవి** (`terraform/main.tf`):
- **VPC:** 2 public + 2 private subnets, ఒకే NAT gateway (చవక).
- **EKS cluster:** Kubernetes 1.31, 2 nodes (`t3.medium`). `enable_cluster_creator_admin_permissions = true` వల్ల cluster ని తయారు చేసిన GitHub role మాత్రమే admin. అందుకే మీ లోకల్ user కి `kubectl` access ఇవ్వాలంటే access entry చేర్చాలి (README troubleshooting చూడండి).
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

*Run workflow → destroy.* Workflow ఇలా చేస్తుంది:
1. ముందు ArgoCD app ని తొలగిస్తుంది. లేకపోతే app తయారు చేసిన load balancers, volumes AWS లో మిగిలిపోతాయి, VPC తొలగడం ఆగిపోతుంది.
2. తర్వాత `terraform destroy` తో cluster, VPC, NAT అన్నీ తొలగిస్తుంది.

**Destroy తొలగించనివి:** S3 bucket, IAM role, OIDC provider. అవి script తయారు చేసినవి, Terraform కాదు. ఖర్చు దాదాపు లేదు, కానీ role కి Admin అనుమతులు ఉన్నాయి. పూర్తిగా ముగించేస్తే వాటిని కూడా తొలగించండి. State bucket ని cluster తొలగిన **తర్వాత** మాత్రమే తొలగించాలి.

## సాధారణ errors

| Error | కారణం | పరిష్కారం |
|---|---|---|
| `aws-region` not supplied | Variables ఇంకో environment లో ఉన్నాయి, లేదా అసలు లేవు | Repository variables పెట్టండి, లేదా job లో `environment:` వాడండి |
| Could not load credentials | `AWS_ROLE_ARN` secret లేదు | Secret తయారు చేయండి |
| Not authorized to AssumeRoleWithWebIdentity | `sub` పేరు/ID రూపం trust policy తో సరిపోలలేదు | Trust policy లో రెండు రూపాలూ చేర్చండి |
| kubectl: must be logged in | Cluster admin గా GitHub role మాత్రమే ఉంది | మీ user కి access entry ఇవ్వండి |

Fix తర్వాత "Re-run" వాడకండి. అది పాత commit నే వాడుతుంది. *Run workflow* తో కొత్త run మొదలుపెట్టండి.
