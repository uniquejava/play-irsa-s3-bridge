# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project demonstrates cross-account S3 access from AWS EKS pods using IAM Roles for Service Accounts (IRSA). The architecture spans two AWS accounts and uses a FastAPI application for testing:

- **Account A** (488363440930): Hosts EKS cluster with IRSA-enabled FastAPI pods
- **Account B** (498136949440): Contains the S3 bucket accessed cross-account

## Architecture

### Core Components

1. **Account A (EKS Account)**:
   - EKS cluster `cyper-s3bridge-staging-eks` with IRSA enabled
   - VPC with private subnets and NAT gateway
   - IAM role `cyper-s3bridge-staging-pod-role` for pods with cross-account permissions
   - FastAPI application for IRSA functionality verification

2. **Account B (S3 Account)**:
   - S3 bucket `cyper-s3bridge-test-bucket-1762272055`
   - IAM role `s3bridge-cross-account-role` for cross-account access
   - S3 access policies attached to cross-account role

3. **Kubernetes Resources**:
   - ServiceAccount `s3bridge` with IRSA annotation
   - FastAPI application deployment with health checks
   - Service for internal access

### Key Security Features

- **IRSA (IAM Roles for Service Accounts)**: Provides pod-level IAM credentials without manual AK/SK
- **Cross-account IAM role assumption**: Secure delegation between accounts
- **Principle of least privilege**: Granting only necessary S3 permissions
- **Professional naming**: Uses `s3bridge` business naming instead of test names

## Common Development Commands

### Environment Setup

Ensure AWS CLI is configured with appropriate profiles:
- Account A (EKS): `pes_songbai` profile
- Account B (S3): `xiaohao-4981` profile

### Manual Terraform Operations

```bash
# Initialize Terraform in each account directory
cd account-a && terraform init
cd account-b && terraform init

# Deploy Account A first (EKS cluster and pod role)
cd account-a
AWS_PROFILE=pes_songbai terraform apply \
  -var="aws_region=ap-northeast-1" \
  -var="cluster_name=cyper-s3bridge-staging-eks" \
  -var="s3_bucket_account_id=498136949440" \
  -auto-approve

# Get pod role ARN for Account B
POD_ROLE_ARN=$(AWS_PROFILE=pes_songbai terraform output -raw pod_role_arn)

# Deploy Account B (S3 bucket with cross-account role)
cd ../account-b
AWS_PROFILE=xiaohao-4981 terraform apply \
  -var="aws_region=ap-northeast-1" \
  -var="s3_bucket_name=cyper-s3bridge-test-bucket-1762272055" \
  -var="eks_account_role_arn=$POD_ROLE_ARN" \
  -auto-approve
```

### Kubernetes Operations

```bash
# Configure kubectl for EKS cluster (using Account A profile)
AWS_PROFILE=pes_songbai aws eks update-kubeconfig \
  --region ap-northeast-1 \
  --name cyper-s3bridge-staging-eks

# Build and push FastAPI application image
cd testing-app
docker build -t uniquejava/irsa-test:latest .
docker push uniquejava/irsa-test:latest

# Deploy FastAPI application
cd ../account-a
kubectl apply -f 12-k8s-s3bridge.yaml

# Wait for pod readiness
kubectl wait --for=condition=ready pod -l app=s3bridge --timeout=120s

# Set up port forwarding for testing
kubectl port-forward service/s3bridge-service 8080:80 &
```

### FastAPI Application Testing

```bash
# Health check endpoint
curl http://localhost:8080/health

# IRSA identity verification
curl http://localhost:8080/identity

# Cross-account S3 access test
curl http://localhost:8080/s3-test

# Application info
curl http://localhost:8080/
```

## Project Structure

```
play-irsa-s3-bridge/
├── CLAUDE.md                     # This file - Claude Code guidance
├── README.md                     # Main project documentation
├── NOTES.md                      # Technical implementation notes
├── account-a/                    # Account A (EKS account) configuration
│   ├── 1-vpc.tf                  # VPC network configuration
│   ├── 2-eks-cluster.tf          # EKS cluster configuration
│   ├── 3-eks-nodegroup.tf        # EKS node group configuration
│   ├── 9-irsa-oidc.tf            # IRSA OIDC provider
│   ├── 10-irsa-pod-role.tf       # Pod IAM role
│   ├── 11-irsa-policy.tf         # IRSA access policies
│   └── 12-k8s-s3bridge.yaml      # Kubernetes deployment configuration
├── account-b/                    # Account B (S3 account) configuration
│   ├── 1-s3-bucket.tf            # S3 bucket configuration
│   ├── 2-iam-role.tf             # Cross-account IAM role
│   └── 3-s3-policy.tf            # S3 access policies
└── testing-app/                  # FastAPI test application
    ├── app.py                    # FastAPI application with test endpoints
    ├── Dockerfile                # Container build (Alibaba Cloud optimized)
    ├── requirements.txt          # Python dependencies
    └── README.md                 # Application documentation
```

## Important Configuration Details

### AWS Authentication
- Uses AWS profiles configured in ~/.aws/config and ~/.aws/credentials
- Account A profile: pes_songbai (EKS account)
- Account B profile: xiaohao-4981 (S3 account)
- All Terraform commands must specify appropriate AWS_PROFILE

### FastAPI Application
- **Image**: `uniquejava/irsa-test:latest` on Docker Hub
- **Port**: 8080
- **Health check**: `/health` endpoint
- **Test endpoints**: `/identity`, `/s3-test`, `/`
- **Build optimization**: Uses Alibaba Cloud PyPI mirror for faster builds

### EKS Configuration
- Cluster name: `cyper-s3bridge-staging-eks`
- Cluster version: 1.34
- IRSA enabled for IAM role integration
- Managed node group with t3.medium instances
- ServiceAccount name: `s3bridge`

### IAM Role Chain
1. EKS pod assumes `cyper-s3bridge-staging-pod-role` via IRSA
2. Pod role assumes `s3bridge-cross-account-role` in Account B
3. Cross-account role has S3 permissions on target bucket

### ServiceAccount Configuration
The ServiceAccount uses IRSA annotation:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3bridge
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::488363440930:role/cyper-s3bridge-staging-pod-role
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
3. **FastAPI application** is built and deployed after both accounts are configured

## Cleanup Procedures

### Manual Cleanup
```bash
# Delete Kubernetes resources first
kubectl delete -f account-a/12-k8s-s3bridge.yaml

# Destroy Account B resources (S3 bucket)
cd account-b
AWS_PROFILE=xiaohao-4981 terraform destroy \
  -var="aws_region=ap-northeast-1" \
  -var="s3_bucket_name=cyper-s3bridge-test-bucket-1762272055" \
  -var="eks_account_role_arn=arn:aws:iam::488363440930:role/cyper-s3bridge-staging-pod-role" \
  -auto-approve

# Destroy Account A resources (EKS cluster)
cd ../account-a
AWS_PROFILE=pes_songbai terraform destroy \
  -var="aws_region=ap-northeast-1" \
  -var="cluster_name=cyper-s3bridge-staging-eks" \
  -var="s3_bucket_account_id=498136949440" \
  -auto-approve
```

## Testing and Verification

### Expected Test Results

1. **Health Check**: `{"status":"healthy"}`
2. **Identity**: Account A (488363440930) IRSA credentials
3. **S3 Access**: Successful cross-account file read from Account B bucket

### Troubleshooting Commands
```bash
# Check pod status
kubectl get pods -l app=s3bridge
kubectl logs -l app=s3bridge

# Verify ServiceAccount configuration
kubectl get serviceaccount s3bridge -o yaml

# Test network connectivity
kubectl exec -it deployment/s3bridge-app -- curl -I https://sts.ap-northeast-1.amazonaws.com
```

## Key Implementation Notes

- **Professional naming**: All resources use `s3bridge` naming convention
- **Zero configuration**: No manual AK/SK credentials required in pods
- **Optimized builds**: Docker builds use Alibaba Cloud mirrors for speed
- **Complete testing**: FastAPI app provides comprehensive IRSA validation
- **Cross-account security**: IAM role chain ensures secure delegation

*Project Status: ✅ Complete - IRSA cross-account S3 access fully implemented and tested*