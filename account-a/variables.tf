variable "cross_account_s3_role_arn" {
  description = "ARN of the cross-account S3 role in Account B that EKS pods will assume"
  type        = string

  # 默认值，实际使用时需要传入正确的 Account B 角色 ARN
  default = "arn:aws:iam::498136949440:role/s3bridge-cross-account-role"
}