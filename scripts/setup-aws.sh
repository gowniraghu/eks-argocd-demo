#!/usr/bin/env bash
# One-time AWS setup: state bucket + GitHub OIDC login + IAM role for GitHub Actions.
# Usage: ./scripts/setup-aws.sh <github-user> <repo-name> [region]
# Run it with your own AWS credentials (aws configure / aws sso login) in a learning account.
set -euo pipefail

GH_USER="${1:?usage: $0 <github-user> <repo-name> [region]}"
REPO="${2:?usage: $0 <github-user> <repo-name> [region]}"
REGION="${3:-eu-west-1}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="tfstate-${ACCOUNT_ID}-${REGION}"
ROLE="github-actions-eks-demo"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

echo "Account: $ACCOUNT_ID  Region: $REGION"

# 1. Bucket that stores Terraform state
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION"
  fi
  aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
fi

# 2. Let GitHub Actions log in to AWS without stored keys
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
fi

# 3. Role that only YOUR repo can assume
cat > /tmp/trust.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "${OIDC_ARN}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
      "StringLike": {"token.actions.githubusercontent.com:sub": "repo:${GH_USER}/${REPO}:*"}
    }
  }]
}
JSON
aws iam create-role --role-name "$ROLE" --assume-role-policy-document file:///tmp/trust.json >/dev/null 2>&1 \
  || aws iam update-assume-role-policy --role-name "$ROLE" --policy-document file:///tmp/trust.json
aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

cat <<OUT

Done. Add these in GitHub (repo > Settings > Secrets and variables > Actions):
  Secret   AWS_ROLE_ARN      = arn:aws:iam::${ACCOUNT_ID}:role/${ROLE}
  Variable AWS_REGION        = ${REGION}
  Variable TF_STATE_BUCKET   = ${BUCKET}
OUT
