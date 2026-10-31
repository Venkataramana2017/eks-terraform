# Committed on purpose: no secrets here. Keep region in sync with the
# AWS_REGION GitHub variable, and cluster_name in sync with bootstrap/.
region             = "us-east-1"
cluster_name       = "demo-eks"
kubernetes_version = "1.33"

node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 4

# admin_principal_arns = ["arn:aws:iam::123456789012:role/my-admin-role"]
