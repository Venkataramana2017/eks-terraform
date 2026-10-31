variable "region" {
  description = "AWS region for the cluster"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name. Must match cluster_name in bootstrap/ (IAM permissions are scoped to this prefix)"
  type        = string
  default     = "demo-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version (check the EKS supported versions list before applying)"
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets/nodes across"
  type        = number
  default     = 2
}

variable "node_instance_types" {
  description = "Instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  description = "Initial desired node count (changes after creation are ignored so autoscalers can manage it)"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum node count"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum node count"
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Node root volume size in GiB"
  type        = number
  default     = 30
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Restrict this outside of demos"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arns" {
  description = "Extra IAM role/user ARNs to grant cluster-admin (do not include the identity running terraform, it already gets admin)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Project   = "eks-demo"
  }
}
