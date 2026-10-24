# One-time bootstrap. Run locally with admin credentials.
# Creates: S3 state bucket, GitHub OIDC provider, and two IAM roles for GitHub Actions
#   - plan role  : read-only, assumable from pull requests
#   - apply role : can create the EKS stack, assumable only from main / the "production" environment

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.81"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform state"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in owner/repo form"
  type        = string
}

variable "cluster_name" {
  description = "Must match cluster_name in ../terraform/terraform.tfvars"
  type        = string
  default     = "demo-eks"
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "github_environment" {
  description = "GitHub Environment used for the manual approval gate on apply/destroy"
  type        = string
  default     = "production"
}

variable "create_github_oidc_provider" {
  description = "Set false if the account already has the token.actions.githubusercontent.com OIDC provider"
  type        = bool
  default     = true
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

############################################
# Terraform state bucket
############################################
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

############################################
# GitHub OIDC provider
############################################
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

############################################
# Trust policies
############################################
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # plan job on main uses the ref claim; the apply job (with an environment) uses the environment claim
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}",
        "repo:${var.github_repo}:environment:${var.github_environment}",
      ]
    }
  }
}

############################################
# Permissions
############################################
data "aws_iam_policy_document" "state_read" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

data "aws_iam_policy_document" "apply" {
  statement {
    sid       = "StateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "NetworkAndCompute"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  statement {
    sid       = "Eks"
    actions   = ["eks:*"]
    resources = ["*"]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:*"]
    resources = ["*"]
  }

  statement {
    sid     = "ClusterRolesAndPolicies"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${var.cluster_name}-*",
      "arn:aws:iam::${local.account_id}:policy/${var.cluster_name}-*",
    ]
  }

  statement {
    sid = "EksOidcProvider"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
    ]
    resources = ["arn:aws:iam::${local.account_id}:oidc-provider/oidc.eks.*"]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/*"]
  }
}

############################################
# Roles
############################################
resource "aws_iam_role" "plan" {
  name               = "${var.cluster_name}-gha-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "state-read"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_read.json
}

resource "aws_iam_role" "apply" {
  name               = "${var.cluster_name}-gha-apply"
  assume_role_policy = data.aws_iam_policy_document.apply_trust.json
}

resource "aws_iam_role_policy" "apply" {
  name   = "eks-stack-deploy"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}

############################################
# Outputs: copy these into GitHub repo variables
############################################
output "TF_STATE_BUCKET" {
  value = aws_s3_bucket.state.bucket
}

output "AWS_PLAN_ROLE_ARN" {
  value = aws_iam_role.plan.arn
}

output "AWS_APPLY_ROLE_ARN" {
  value = aws_iam_role.apply.arn
}
