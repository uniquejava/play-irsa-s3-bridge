# 跨账户访问IAM角色
# 这个角色将被Account A中的EKS Pod扮演

resource "aws_iam_role" "s3_cross_account_role" {
  name = "s3bridge-cross-account-role"
  description = "IAM role for cross-account S3 access from EKS pods"

  # 信任策略：只允许Account A的特定Pod角色扮演
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          AWS = var.eks_account_role_arn # Account A的Pod角色ARN
        }
        # 可选：添加外部ID以增强安全性
        # Condition {
        #   StringEquals = {
        #     "sts:ExternalId" = "unique-external-id"
        #   }
        # }
      }
    ]
  })

  tags = {
    Project = "s3bridge"
    Purpose = "cross-account-s3-access"
  }
}