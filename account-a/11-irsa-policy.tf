# 跨账户角色扮演策略
# 允许 EKS Pod 角色扮演 Account B 中的 S3 访问角色

resource "aws_iam_policy" "assume_cross_account_role_policy" {
  name        = "${local.prefix}-assume-cross-account-role-policy"
  description = "Policy allowing EKS pods to assume cross-account S3 role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        # 这里需要 Account B 中的角色 ARN
        # 将通过变量传入，格式：arn:aws:iam::ACCOUNT_B_ID:role/s3bridge-cross-account-role
        Resource = var.cross_account_s3_role_arn
      }
    ]
  })

  tags = local.tags
}

# 将策略附加到 Pod 角色
resource "aws_iam_role_policy_attachment" "pod_role_cross_account_attachment" {
  role       = aws_iam_role.eks_pod_role.name
  policy_arn = aws_iam_policy.assume_cross_account_role_policy.arn
}

# 添加基本的 AWS 权限策略（用于测试和调试）
resource "aws_iam_role_policy_attachment" "pod_role_basic_s3_access" {
  role       = aws_iam_role.eks_pod_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}