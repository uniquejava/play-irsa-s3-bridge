provider "aws" {
  region = local.region
}

terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "cyper-s3bridge-tf-state-account-a"
    key          = "account-a/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}