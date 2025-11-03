terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "s3bridge-tf-state-account-a"
    key          = "account-a/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true # Terraform 1.10+ 原生锁
  }
}

provider "aws" {
  region = var.aws_region
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.8.0"

  name                    = var.cluster_name
  kubernetes_version      = "1.34"
  enable_irsa             = true # Key: Enable IRSA

  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_subnets

  endpoint_public_access  = true # For kubectl access

  eks_managed_node_groups = {
    s3bridge_nodes = {
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      instance_types = ["t3.medium"]
    }
  }

  tags = {
    Project = "s3bridge"
  }
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "192.168.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}c"]
  private_subnets = ["192.168.1.0/24", "192.168.2.0/24"]
  public_subnets  = ["192.168.101.0/24", "192.168.102.0/24"]

  enable_nat_gateway   = true
  enable_dns_hostnames = true
}

# S3 VPC Endpoint (节约成本)
resource "aws_vpc_endpoint" "s3" {
  vpc_id          = module.vpc.vpc_id
  service_name    = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = module.vpc.private_route_table_ids

  tags = {
    Name = "s3-vpc-endpoint"
  }
}

# EKS Pod使用的IAM角色
resource "aws_iam_role" "eks_pod_role" {
  name = "${var.cluster_name}-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:default:s3bridge-app"
        }
      }
    }]
  })
}

# 允许扮演Account B角色的策略
resource "aws_iam_policy" "assume_role_policy" {
  name = "${var.cluster_name}-assume-role-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::${var.s3_bucket_account_id}:role/s3bridge-cross-account-role"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "pod_role_attachment" {
  role       = aws_iam_role.eks_pod_role.name
  policy_arn = aws_iam_policy.assume_role_policy.arn
}

