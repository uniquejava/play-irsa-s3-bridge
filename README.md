# S3 Bridge: Cross-Account S3 Access from EKS using IRSA

This project demonstrates cross-account S3 access from AWS EKS pods using IAM Roles for Service Accounts (IRSA) with VPC Endpoints for cost optimization. The architecture spans two AWS accounts and showcases secure, cost-effective cross-account resource access.

## Architecture Overview

```
┌─────────────────┐          ┌─────────────────┐
│   Account A     │          │   Account B     │
│   (EKS Account) │          │   (S3 Account)  │
├─────────────────┤          ├─────────────────┤
│                 │          │                 │
│  ┌───────────┐  │          │  ┌───────────┐  │
│  │EKS Cluster│  │ IRSA +   │  │ S3 Bucket │  │
│  │           │  │Cross-Acct│  │           │  │
│  └─────┬─────┘  │ Role Ass. │  └───────────┘  │
│        │        │   ───────▶│                 │
│  ┌─────▼─────┐  │          │  ┌───────────┐  │
│  │Test Pod   │  │          │  │Cross-Acct │  │
│  │with IRSA  │─┼──────────▶│  │S3 Role    │  │
│  └───────────┘  │          │  └───────────┘  │
│        │        │          │                 │
│  ┌─────▼─────┐  │          │                 │
│  │S3 VPC     │  │          │                 │
│  │Endpoint   │◀─┼──────────┤                 │
│  │(Gateway)  │  │ Private  │                 │
│  └───────────┘  │ Link     │                 │
└─────────────────┘          └─────────────────┘
```

### Key Components

**Account A (EKS Account)**:
- EKS cluster with IRSA enabled
- VPC with S3 VPC Endpoint (Gateway type) for private S3 access
- IAM role for EKS pods with cross-account assume role permissions
- Terraform state management

**Account B (S3 Account)**:
- S3 bucket for cross-account access
- IAM role that can be assumed by Account A's pod role
- S3 access policies attached to cross-account role
- Terraform state management

**Security Features**:
- **IRSA**: Pod-level IAM credentials
- **Cross-account IAM role assumption**: Secure delegation between accounts
- **VPC Endpoint**: S3 traffic stays within AWS backbone (cost optimization)
- **Principle of least privilege**: Only necessary S3 permissions granted

## Prerequisites

- Terraform >= 1.10.0
- AWS CLI configured with profiles for both accounts
- kubectl
- Bash shell (for deployment scripts)

## Quick Start

### 1. Configure Environment

Copy and configure the environment file:

```bash
cp .env.example .env
# Edit .env with your AWS account details
```

Required environment variables:
```bash
# Account A (EKS Account)
ACCOUNT_A_ID=111111111111
ACCOUNT_A_PROFILE=your-account-a-profile

# Account B (S3 Account)
ACCOUNT_B_ID=222222222222
ACCOUNT_B_PROFILE=your-account-b-profile

# AWS Configuration
AWS_REGION=ap-northeast-1
CLUSTER_NAME=s3bridge-cluster
S3_BUCKET_NAME=s3bridge-demo-bucket-$(date +%s)  # Auto-generates unique name
```

**⚠️ Important: Check for VPC CIDR Conflicts**
Before deploying, ensure you don't have existing VPCs with overlapping CIDR blocks:
```bash
aws ec2 describe-vpcs --region $AWS_REGION \
  --query 'Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output table

# If you see overlapping CIDRs (e.g., multiple 10.0.0.0/16),
# destroy the conflicting VPCs first
```

### 2. Deploy Infrastructure

**Automated Deployment (Recommended)**:
```bash
./scripts/deploy.sh
```

This single command handles:
- Terraform state bucket setup
- Cross-account dependency resolution
- EKS cluster deployment with IRSA
- S3 bucket creation with cross-account access
- Kubernetes configuration
- Test pod deployment
- Cross-account S3 access verification

**Manual Deployment**:
```bash
# Step 1: Set up Terraform state buckets
./scripts/setup-state-buckets.sh

# Step 2: Deploy Account A (EKS)
cd account-a
terraform init
terraform apply \
  -var="aws_region=$AWS_REGION" \
  -var="cluster_name=$CLUSTER_NAME" \
  -var="s3_bucket_account_id=$ACCOUNT_B_ID" \
  -auto-approve

# Step 3: Get pod role ARN
POD_ROLE_ARN=$(terraform output -raw pod_role_arn)

# Step 4: Deploy Account B (S3)
cd ../account-b
terraform init
terraform apply \
  -var="aws_region=$AWS_REGION" \
  -var="s3_bucket_name=$S3_BUCKET_NAME" \
  -var="eks_account_role_arn=$POD_ROLE_ARN" \
  -auto-approve

# Step 5: Configure kubectl
AWS_PROFILE=$ACCOUNT_A_PROFILE aws eks update-kubeconfig \
  --region $AWS_REGION \
  --name $CLUSTER_NAME

# Step 6: Deploy test pod
sed "s/<ACCOUNT_A_POD_ROLE_ARN>/$POD_ROLE_ARN/g" k8s/test-pod.yaml > k8s/test-pod-updated.yaml
kubectl apply -f k8s/test-pod-updated.yaml

# Step 7: Test S3 access
export S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
bash k8s/verify-scripts/test-s3-access.sh
```

### 3. Verify Cross-Account Access

The deployment script automatically runs verification tests. You can also run them manually:

```bash
# Check pod identity
kubectl exec -it s3bridge-test-pod -- aws sts get-caller-identity

# Test S3 bucket access
kubectl exec -it s3bridge-test-pod -- aws s3 ls s3://$S3_BUCKET_NAME/

# Test S3 write access
kubectl exec -it s3bridge-test-pod -- sh -c "echo 'Hello from S3Bridge Pod' > /tmp/test.txt"
kubectl exec -it s3bridge-test-pod -- aws s3 cp /tmp/test.txt s3://$S3_BUCKET_NAME/test-pod-access.txt

# Verify write
kubectl exec -it s3bridge-test-pod -- aws s3 cp s3://$S3_BUCKET_NAME/test-pod-access.txt /tmp/verify.txt
kubectl exec -it s3bridge-test-pod -- cat /tmp/verify.txt
```

## Cost Optimization Features

### VPC S3 Gateway Endpoint
- Eliminates NAT Gateway costs for S3 traffic
- S3 access stays within AWS backbone network
- No data transfer charges for S3 access from private subnets

### Infrastructure Scale
- EKS: 2 t3.medium instances (minimum viable)
- S3: Pay-per-use storage and requests
- VPC Endpoint: No hourly charge, only per-GB data processing

## Cleanup

### Automated Cleanup
```bash
./scripts/destroy.sh
```

This removes all resources in the correct order and offers optional state bucket cleanup.

### Manual Cleanup
```bash
# Delete Kubernetes resources
kubectl delete -f k8s/test-pod-updated.yaml --ignore-not-found=true

# Destroy Account A resources
cd account-a
terraform destroy \
  -var="aws_region=$AWS_REGION" \
  -var="cluster_name=$CLUSTER_NAME" \
  -var="s3_bucket_account_id=$ACCOUNT_B_ID" \
  -auto-approve

# Destroy Account B resources
cd ../account-b
terraform destroy \
  -var="aws_region=$AWS_REGION" \
  -var="s3_bucket_name=$S3_BUCKET_NAME" \
  -var="eks_account_role_arn=arn:aws:iam::${ACCOUNT_A_ID}:role/s3bridge-cluster-pod-role" \
  -auto-approve

# Clean up state buckets (optional)
./scripts/cleanup-state-buckets.sh
```

## Project Structure

```
play-irsa-s3-bridge/
├── .env                         # AWS account configuration
├── scripts/                     # Automation scripts
│   ├── deploy.sh               # Complete deployment automation
│   ├── destroy.sh              # Complete cleanup automation
│   ├── setup-state-buckets.sh  # Terraform state bucket setup
│   └── cleanup-state-buckets.sh # State bucket cleanup
├── account-a/                   # EKS cluster and pod IAM configuration
│   ├── main.tf                 # EKS, VPC, VPC Endpoint, IAM roles
│   ├── variables.tf            # Input variables
│   └── outputs.tf              # EKS cluster and pod role outputs
├── account-b/                   # S3 bucket and cross-account access
│   ├── main.tf                 # S3 bucket, cross-account IAM role
│   ├── variables.tf            # Input variables
│   └── outputs.tf              # S3 bucket and cross-account role outputs
├── k8s/                         # Kubernetes manifests and scripts
│   ├── test-pod.yaml          # ServiceAccount and test pod (template)
│   └── verify-scripts/
│       └── test-s3-access.sh  # Cross-account S3 verification script
├── CLAUDE.md                   # Claude Code guidance
└── README.md                   # This file
```

## Security Considerations

### IAM Role Chain
1. EKS pod assumes `s3bridge-cluster-pod-role` via IRSA
2. Pod role assumes `s3bridge-cross-account-role` in Account B
3. Cross-account role has S3 permissions on target bucket

### Network Security
- S3 traffic uses VPC Gateway Endpoint (stays within AWS network)
- No internet gateway required for S3 access
- Private subnets for enhanced security

### Access Control
- Pod role restricted to specific ServiceAccount
- Cross-account role restricted to specific S3 bucket
- Least privilege permissions enforced

## Troubleshooting

### Common Issues

**Terraform State Bucket Errors**:
```bash
# Re-initialize state buckets
./scripts/setup-state-buckets.sh
```

**Pod Cannot Assume Cross-Account Role**:
- Verify Account B's trust policy includes Account A's pod role ARN
- Check pod role has sts:AssumeRole permissions for Account B's role

**S3 Access Denied**:
- Verify cross-account role has proper S3 permissions
- Check S3 bucket policy allows cross-account access
- Ensure VPC endpoint is properly configured

**kubectl Connection Issues**:
```bash
# Refresh kubeconfig
AWS_PROFILE=$ACCOUNT_A_PROFILE aws eks update-kubeconfig \
  --region $AWS_REGION \
  --name $CLUSTER_NAME
```

**EKS Node Group Creation Failed**:
- **VPC CIDR Conflicts**: Check for overlapping VPC CIDR blocks
```bash
# Check for VPC CIDR conflicts in your target region
aws ec2 describe-vpcs --region $AWS_REGION \
  --query 'Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output table

# Example output showing conflicting CIDRs:
# -------------------------------------------
# |            DescribeVpcs                |
# +----------------------+-----------------+
# | vpc-0123456789abcdef0|  10.0.0.0/16    |
# | vpc-0fedcba9876543210|  10.0.0.0/16    |  <- CONFLICT!
# | vpc-abcdef1234567890|  192.168.0.0/16  |
# -------------------------------------------

# If you find overlapping CIDRs (e.g., multiple VPCs with 10.0.0.0/16),
# you must either:
# 1. Destroy the conflicting VPC(s), OR
# 2. Update your project's CIDR range in account-a/main.tf
```
- **Symptom**: `NodeCreationFailure: Unhealthy nodes in the kubernetes cluster`
- **Root Cause**: EKS nodes cannot join the cluster when multiple VPCs in the same region have overlapping CIDR blocks
- **Solution**: This project uses `192.168.0.0/16` to avoid common conflicts with default 10.0.0.0/16 ranges
- **Note**: VPC CIDR conflicts cannot be prevented in Terraform code as they involve resources outside the project scope

### Verification Commands

```bash
# Check Terraform state
terraform state list

# Verify AWS credentials
aws sts get-caller-identity

# Check pod status
kubectl get pods -o wide

# Check ServiceAccount
kubectl get serviceaccount s3bridge-app -o yaml

# Test network connectivity
kubectl exec -it s3bridge-test-pod -- nc -zv s3.ap-northeast-1.amazonaws.com 443
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is for educational and demonstration purposes. Use at your own risk and ensure proper security measures in production environments.