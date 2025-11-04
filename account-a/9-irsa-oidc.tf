# IRSA 需要的 OIDC 提供者
# 用于 EKS 集群的 Pod 身份验证

data "aws_iam_policy_document" "oidc_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks_oidc.arn]
    }

    # 限制只有特定的 ServiceAccount 可以扮演这个角色
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks_oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:default:s3bridge"]
    }
  }
}

# 创建 EKS 集群的 OIDC 提供者
resource "aws_iam_openid_connect_provider" "eks_oidc" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = local.tags
}

# 获取 EKS 集群的 OIDC 证书
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}