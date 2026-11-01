terraform {
  required_version = ">= 1.6"

  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.80" }
    helm = { source = "hashicorp/helm", version = "~> 2.17" }
  }

  # Bucket/key/region are passed with -backend-config in the workflow.
  backend "s3" {}
}
