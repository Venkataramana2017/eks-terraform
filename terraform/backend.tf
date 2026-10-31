# The default region matches var.region; override it with -backend-config when
# the state bucket is in a different region.
# use_lockfile = S3 native state locking (Terraform >= 1.10), no DynamoDB needed.
terraform {
  backend "s3" {
    bucket       = "bucket-backend-terraform-313932316713-us-east-1"
    key          = "eks/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}