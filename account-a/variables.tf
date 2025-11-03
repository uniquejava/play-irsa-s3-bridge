variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "s3bridge-cluster"
}

variable "s3_bucket_account_id" {
  description = "Account ID where S3 bucket is located"
  type        = string
}