variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
  default     = "s3bridge-demo-bucket"
}

variable "eks_account_role_arn" {
  description = "ARN of the EKS pod role in Account A"
  type        = string
}