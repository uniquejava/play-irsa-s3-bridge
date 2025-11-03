output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.cross_account_bucket.bucket
}

output "cross_account_role_arn" {
  description = "Cross account role ARN"
  value       = aws_iam_role.s3_cross_account_role.arn
}