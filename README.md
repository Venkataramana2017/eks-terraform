# EKS on AWS with Terraform and GitHub Actions

```
bootstrap/                    one-time: S3 state bucket + GitHub OIDC + 2 IAM roles (plan / apply)
terraform/                    the EKS stack
  vpc.tf                      VPC, 2 public + 2 private subnets, IGW, single NAT
  iam.tf                      cluster role, node role, OIDC provider (IRSA), EBS CSI role
  eks.tf                      cluster, managed node group, add-ons, optional admin access entries
.github/workflows/terraform-eks.yml
```

## What gets created
- VPC across 2 AZs. Nodes sit in private subnets and reach out through one NAT gateway.
- EKS cluster with API-mode access entries, all control-plane logs to CloudWatch, public and private endpoint.
- Managed node group (AL2023, t3.medium, 1-4 nodes, desired 2).
- IAM:
  - **Cluster role**: AmazonEKSClusterPolicy
  - **Node role**: WorkerNode, CNI, ECR read-only, SSM core
  - **OIDC provider** so pods can assume IAM roles (IRSA)
  - **EBS CSI role** bound to `kube-system/ebs-csi-controller-sa`
- Add-ons: vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver.

## Setup
1. **Bootstrap** (local, admin credentials):
   ```bash
   cd bootstrap
   cp terraform.tfvars.example terraform.tfvars   # set bucket name + github_repo
   terraform init && terraform apply
   ```
   Keep the local state for this folder, or migrate it later. The outputs are your GitHub variable values.
2. **GitHub repo, Settings > Secrets and variables > Actions > Variables**:
   `AWS_REGION`, `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`
   (no long-lived AWS keys are stored anywhere).
3. **Settings > Environments > New environment** named `production`, add required reviewers.
4. Run `terraform fmt -recursive` once locally, commit, and push.
   - Pull request: fmt, validate, plan (comment on the PR, read-only role)
   - Merge to main: plan, approval, apply
   - Actions tab > Run workflow > `destroy`: tears everything down (also needs approval)

## Setup option B: bootstrap from GitHub Actions (no local Terraform needed)
1. Create a temporary IAM user with admin rights and an access key.
2. In the repo add **secrets** `BOOTSTRAP_AWS_ACCESS_KEY_ID` and `BOOTSTRAP_AWS_SECRET_ACCESS_KEY`,
   and the **variable** `AWS_REGION`.
3. Create the `production` environment (with required reviewers).
4. Actions tab > *EKS Terraform* > Run workflow > action = `bootstrap`. Run it once only.
5. Open the run summary, copy `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN` into repo variables.
6. **Delete the two bootstrap secrets and the temporary IAM access key.**
7. Run the workflow with action = `apply` (or push to main).

## Local use
```bash
cd terraform
terraform init \
  -backend-config="bucket=<TF_STATE_BUCKET>" \
  -backend-config="key=eks/terraform.tfstate" \
  -backend-config="region=us-east-1"
terraform apply
aws eks update-kubeconfig --region us-east-1 --name demo-eks
kubectl get nodes
```
Replace `us-east-1` with the region containing your S3 state bucket. Pass the
bucket, key, and region as shown; if Terraform prompts for the bucket or key,
the backend config was not supplied correctly.
To give yourself kubectl access when the pipeline created the cluster, add your IAM role/user ARN to `admin_principal_arns` in `terraform.tfvars`.

If `terraform plan` reports `403 Forbidden` while reading the S3 state object,
check that the active AWS identity has `s3:ListBucket` on the bucket and
`s3:GetObject` on the state object, and confirm the bucket and key match your
existing state. This project uses `eks/terraform.tfstate`; only switch to that
key if it is where your state is stored, since a different key may make
Terraform see an empty state. For local use, check the active identity with
`aws sts get-caller-identity`.

## Notes
- `cluster_name` and `region` in `terraform/terraform.tfvars` must match `bootstrap` and the `AWS_REGION` variable.
- Cost: EKS control plane (~$0.10/hr) + NAT gateway + 2 nodes. Destroy when finished.
- `public_access_cidrs` defaults to `0.0.0.0/0`; restrict it beyond demos.
- The apply role's IAM permissions are scoped by `<cluster_name>-*` name prefix, not a permissions boundary. If an apply fails with AccessDenied, add the action named in the error.
- Commit `terraform/.terraform.lock.hcl` after the first `init` so CI uses the same provider versions.
- Check `kubernetes_version` against the currently supported EKS versions before applying.
- Next steps: AWS Load Balancer Controller, Cluster Autoscaler or Karpenter (each needs its own IRSA role; reuse `oidc_provider_arn`).
