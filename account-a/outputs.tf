# EKS 集群信息
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.eks.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.eks.endpoint
}

# IRSA 相关输出
output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = aws_iam_openid_connect_provider.eks_oidc.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL for IRSA"
  value       = aws_iam_openid_connect_provider.eks_oidc.url
}

output "pod_role_arn" {
  description = "IAM role ARN for EKS pods (this will be used in ServiceAccount)"
  value       = aws_iam_role.eks_pod_role.arn
}

output "pod_role_name" {
  description = "IAM role name for EKS pods"
  value       = aws_iam_role.eks_pod_role.name
}

# 跨账户访问相关输出
output "cross_account_assume_policy_arn" {
  description = "Policy ARN for cross-account role assumption"
  value       = aws_iam_policy.assume_cross_account_role_policy.arn
}