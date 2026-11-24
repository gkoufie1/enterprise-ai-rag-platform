# Remote state in S3 with native lock files (no DynamoDB lock table needed).
# Settings come from backend.hcl, created by terraform/bootstrap:
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
