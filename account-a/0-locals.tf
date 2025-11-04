locals {
  env = "staging"
  prefix = "cyper-s3bridge-${local.env}"
  region = "ap-northeast-1"
  zone1="ap-northeast-1a"
  zone2="ap-northeast-1c"
  eks_name = "${local.prefix}-eks"
  eks_version = "1.34"

  tags = {
    Environment = local.env
    Project = local.prefix
    Owner = "cyper"
    Terraform = "true"
  }
}