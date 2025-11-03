# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project demonstrates cross-account S3 access from AWS EKS pods using IAM Roles for Service Accounts (IRSA) with VPC Endpoints for cost optimization. The architecture spans two AWS accounts:

- **Account A**: Hosts EKS cluster with pods that need to access S3
- **Account B**: Contains the S3 bucket that needs to be accessed cross-account

## Architecture

### Core Components

1. **Account A (EKS Account)**:
   - EKS cluster with IRSA enabled
   - VPC with S3 VPC Endpoint (Gateway type) for private S3 access
   - IAM role for EKS pods with cross-account assume role permissions
   - Terraform backend using S3 bucket in same account

2. **Account B (S3 Account)**:
   - S3 bucket for cross-account access
   - IAM role that can be assumed by Account A's pod role
   - S3 access policies attached to cross-account role
   - Terraform backend using S3 bucket in same account

3. **Kubernetes Resources**:
   - ServiceAccount with IAM role annotation
   - Test pod using AWS CLI image for verification
   - Verification scripts to test cross-account S3 access

### Key Security Features

- **IRSA (IAM Roles for Service Accounts)**: Provides pod-level IAM credentials
- **Cross-account IAM role assumption**: Secure delegation between accounts
- **VPC Endpoint**: Ensures S3 traffic stays within AWS backbone network
- **Principle of least privilege**: Granting only necessary S3 permissions

## Common Development Commands

### Environment Setup

```bash
# Copy and configure environment variables
cp .env.example .env  # Edit .env with your AWS account details
# Required variables:
# ACCOUNT_A_ID, ACCOUNT_A_PROFILE (EKS account)
# ACCOUNT_B_ID, ACCOUNT_B_PROFILE (S3 account)
# AWS_REGION, CLUSTER_NAME, S3_BUCKET_NAME
```

### Automation Scripts (Recommended)

```bash
# Complete deployment (handles cross-account dependencies automatically)
./scripts/deploy.sh

# Complete cleanup (destroys all resources in correct order)
./scripts/destroy.sh
```

### Manual Terraform Operations

```bash
# Initialize Terraform in each account directory
cd account-a && terraform init
cd account-b && terraform init

# Deploy Account A first (EKS cluster and pod role)
cd account-a
AWS_PROFILE=$ACCOUNT_A_PROFILE terraform apply \
  -var="aws_region=$AWS_REGION" \
  -var="cluster_name=$CLUSTER_NAME" \
  -var="s3_bucket_account_id=$ACCOUNT_B_ID" \
  -auto-approve

# Get pod role ARN for Account B
POD_ROLE_ARN=$(AWS_PROFILE=$ACCOUNT_A_PROFILE terraform output -raw pod_role_arn)

# Deploy Account B (S3 bucket with cross-account role)
cd ../account-b
AWS_PROFILE=$ACCOUNT_B_PROFILE terraform apply \
  -var="aws_region=$AWS_REGION" \
  -var="s3_bucket_name=$S3_BUCKET_NAME" \
  -var="eks_account_role_arn=$POD_ROLE_ARN" \
  -auto-approve
```

### Kubernetes Operations

```bash
# Configure kubectl for EKS cluster (using Account A profile)
AWS_PROFILE=$ACCOUNT_A_PROFILE aws eks update-kubeconfig \
  --region $AWS_REGION \
  --name $CLUSTER_NAME

# Update test pod with correct role ARN (automation scripts handle this)
POD_ROLE_ARN=$(cd account-a && AWS_PROFILE=$ACCOUNT_A_PROFILE terraform output -raw pod_role_arn)
sed "s/<ACCOUNT_A_POD_ROLE_ARN>/$POD_ROLE_ARN/g" k8s/test-pod.yaml > k8s/test-pod-updated.yaml

# Deploy test pod
kubectl apply -f k8s/test-pod-updated.yaml

# Verify S3 access
export S3_BUCKET_NAME=$(cd account-b && AWS_PROFILE=$ACCOUNT_B_PROFILE terraform output -raw s3_bucket_name)
bash k8s/verify-scripts/test-s3-access.sh

# Clean up test pod
kubectl delete -f k8s/test-pod-updated.yaml
rm -f k8s/test-pod-updated.yaml
```

### Testing and Verification

```bash
# Check pod identity
kubectl exec -it s3bridge-test-pod -- aws sts get-caller-identity

# Test cross-account S3 operations
kubectl exec -it s3bridge-test-pod -- aws s3 ls s3://$S3_BUCKET_NAME/
kubectl exec -it s3bridge-test-pod -- aws s3 cp /tmp/test.txt s3://$S3_BUCKET_NAME/test.txt
```

## Project Structure

```
play-irsa-s3-bridge/
├── .env                         # AWS account configuration and environment variables
├── scripts/                     # Automation scripts
│   ├── deploy.sh               # Complete deployment automation
│   └── destroy.sh              # Complete cleanup automation
├── account-a/                   # EKS cluster and pod IAM configuration
│   ├── main.tf                 # EKS, VPC, VPC Endpoint, IAM roles
│   ├── variables.tf            # Input variables (cluster name, S3 account ID)
│   └── outputs.tf              # EKS cluster and pod role outputs
├── account-b/                   # S3 bucket and cross-account access
│   ├── main.tf                 # S3 bucket, cross-account IAM role
│   ├── variables.tf            # Input variables (bucket name, EKS pod role ARN)
│   └── outputs.tf              # S3 bucket and cross-account role outputs
├── k8s/                         # Kubernetes manifests and scripts
│   ├── test-pod.yaml          # ServiceAccount and test pod (template)
│   └── verify-scripts/
│       └── test-s3-access.sh  # Cross-account S3 verification script
└── README.md                   # Deployment instructions in Chinese
```

## Important Configuration Details

### AWS Authentication
- Uses AWS profiles configured in ~/.aws/config and ~/.aws/credentials
- Account A profile: $ACCOUNT_A_PROFILE (default: pes_songbai)
- Account B profile: $ACCOUNT_B_PROFILE (default: xiaohao-4981)
- All Terraform commands must specify appropriate AWS_PROFILE

### Terraform State Management
- Each account uses separate S3 buckets for Terraform state backend
- Terraform version >= 1.10.0 required for native lockfile support
- AWS provider ~> 5.0
- State buckets: s3bridge-tf-state-account-a, s3bridge-tf-state-account-b

### EKS Configuration
- Cluster version: 1.34
- IRSA enabled for IAM role integration
- Managed node group with t3.medium instances
- VPC configuration supports private subnets with NAT gateway

### IAM Role Chain
1. EKS pod assumes `s3bridge-cluster-pod-role` via IRSA
2. Pod role assumes `s3bridge-cross-account-role` in Account B
3. Cross-account role has S3 permissions on target bucket

### VPC Endpoint Configuration
- Gateway type VPC endpoint for S3 (com.amazonaws.ap-northeast-1.s3)
- Associated with private route tables
- Eliminates NAT Gateway costs for S3 traffic

### ServiceAccount Configuration
The ServiceAccount annotation must be updated with the correct pod role ARN:
```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_A:role/s3bridge-cluster-pod-role
```

### Key Terraform Variables
- **account-a**: `cluster_name`, `s3_bucket_account_id`
- **account-b**: `s3_bucket_name`, `eks_account_role_arn`

### Variable Dependencies
The deployment has cross-account dependencies:
- Account B requires `eks_account_role_arn` from Account A
- Account A requires `s3_bucket_account_id` from Account B

These are resolved using Terraform outputs and variable passing during deployment.

## Deployment Workflow

### Cross-Account Dependencies
The deployment has a specific order due to cross-account dependencies:
1. **Account A** creates EKS cluster and pod IAM role
2. **Account B** uses Account A's pod role ARN to create cross-account S3 role
3. **Kubernetes** resources are deployed after both accounts are configured

The automation scripts (`./scripts/deploy.sh`) handle this automatically by:
- Deploying Account A first to get the pod role ARN
- Using that ARN to deploy Account B
- Configuring kubectl and deploying test resources

## Cleanup Procedures

### Automated Cleanup (Recommended)
```bash
./scripts/destroy.sh  # Handles confirmation and correct destruction order
```

### Manual Cleanup
```bash
# Delete Kubernetes resources first
AWS_PROFILE=$ACCOUNT_A_PROFILE aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
kubectl delete -f k8s/test-pod-updated.yaml --ignore-not-found=true

# Destroy Account A resources (EKS cluster)
cd account-a
AWS_PROFILE=$ACCOUNT_A_PROFILE terraform destroy \
  -var="aws_region=$AWS_REGION" \
  -var="cluster_name=$CLUSTER_NAME" \
  -var="s3_bucket_account_id=$ACCOUNT_B_ID" \
  -auto-approve

# Destroy Account B resources (S3 bucket)
cd ../account-b
AWS_PROFILE=$ACCOUNT_B_PROFILE terraform destroy \
  -var="aws_region=$AWS_REGION" \
  -var="s3_bucket_name=$S3_BUCKET_NAME" \
  -var="eks_account_role_arn=arn:aws:iam::${ACCOUNT_A_ID}:role/s3bridge-cluster-pod-role" \
  -auto-approve
```