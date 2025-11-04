# S3存储桶 - 用于跨账户访问测试
# 这个存储桶将被Account A中的EKS Pod访问

resource "aws_s3_bucket" "cross_account_bucket" {
  bucket = var.s3_bucket_name

  tags = {
    Project = "s3bridge"
    Purpose = "cross-account-access-demo"
  }
}

# 配置S3存储桶加密（安全最佳实践）
resource "aws_s3_bucket_server_side_encryption_configuration" "cross_account_bucket_encryption" {
  bucket = aws_s3_bucket.cross_account_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 配置S3存储桶公开访问阻止（安全最佳实践）
resource "aws_s3_bucket_public_access_block" "cross_account_bucket_pab" {
  bucket = aws_s3_bucket.cross_account_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}