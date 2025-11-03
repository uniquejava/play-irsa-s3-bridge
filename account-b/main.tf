terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "cyper-s3bridge-tf-state-account-b"
    key          = "account-b/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

# S3桶
resource "aws_s3_bucket" "cross_account_bucket" {
  bucket = var.s3_bucket_name

  tags = {
    Project = "s3bridge"
  }
}

# 跨账号访问角色
resource "aws_iam_role" "s3_cross_account_role" {
  name = "s3bridge-cross-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        AWS = var.eks_account_role_arn # Account A的Pod角色ARN
      }
    }]
  })
}

# S3访问策略
resource "aws_iam_policy" "s3_access_policy" {
  name = "s3bridge-s3-access-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.cross_account_bucket.arn,
        "${aws_s3_bucket.cross_account_bucket.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_role_attachment" {
  role       = aws_iam_role.s3_cross_account_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

