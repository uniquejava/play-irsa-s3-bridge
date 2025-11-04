# S3访问策略
# 这个策略定义了跨账户角色对S3存储桶的权限

resource "aws_iam_policy" "s3_access_policy" {
  name        = "s3bridge-s3-access-policy"
  description = "Policy for cross-account S3 bucket access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cross_account_bucket.arn,           # 存储桶级别权限
          "${aws_s3_bucket.cross_account_bucket.arn}/*"     # 对象级别权限
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"  # 仅用于基本操作的通配符权限
      }
    ]
  })

  tags = {
    Project = "s3bridge"
    Purpose = "s3-access-policy"
  }
}

# 将S3访问策略附加到跨账户角色
resource "aws_iam_role_policy_attachment" "s3_role_attachment" {
  role       = aws_iam_role.s3_cross_account_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}