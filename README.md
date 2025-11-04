# EKS Cross-Account S3 Access: IRSA Architecture Implementation

Complete solution for EKS pods to access S3 across AWS accounts using IAM Roles for Service Accounts (IRSA), validated with FastAPI application.

English | [简体中文](README.zh-CN.md)

## 🎯 Project Status

**✅ Implementation Complete** - IRSA cross-account S3 access fully implemented and tested

- **Account A** (488363440930): EKS cluster + IRSA configuration
- **Account B** (498136949440): S3 bucket + cross-account role
- **Test Application**: FastAPI service validates all functionality

## 🏗️ Architecture Overview

```
┌─────────────────┐          ┌─────────────────┐
│   Account A     │          │   Account B     │
│  (EKS Account)  │          │  (S3 Account)  │
│  ┌───────────┐  │ IRSA +   │  ┌───────────┐  │
│  │EKS Cluster│  │Cross-Acct│  │ S3 Bucket │  │
│  └─────┬─────┘  │ Role Ass  │  └───────────┘  │
│        │        │   ───────▶│                 │
│  ┌─────▼─────┐  │          │  ┌───────────┐  │
│  │s3bridge   │  │          │  │Cross-Acct │  │
│  │FastAPI Pod│─┼──────────▶│  │S3 Role    │  │
│  └───────────┘  │          │  └───────────┘  │
└─────────────────┘          └─────────────────┘
```

## 🚀 Quick Deployment

### Prerequisites
- AWS CLI configured with two profiles:
  - Account A (EKS): `pes_songbai`
  - Account B (S3): `xiaohao-4981`
- Docker and kubectl installed

### 1. Infrastructure Deployment

```bash
# Account A - EKS cluster and IRSA
cd account-a
terraform init
AWS_PROFILE=pes_songbai terraform apply -auto-approve \
  -var="aws_region=ap-northeast-1" \
  -var="cluster_name=cyper-s3bridge-staging-eks" \
  -var="s3_bucket_account_id=498136949440"

# Account B - S3 bucket and cross-account role
cd ../account-b
terraform init
AWS_PROFILE=xiaohao-4981 terraform apply -auto-approve \
  -var="aws_region=ap-northeast-1" \
  -var="s3_bucket_name=cyper-s3bridge-test-bucket-1762272055" \
  -var="eks_account_role_arn=$(cd ../account-a && AWS_PROFILE=pes_songbai terraform output -raw pod_role_arn)"
```

### 2. Configure kubectl

```bash
AWS_PROFILE=pes_songbai aws eks update-kubeconfig \
  --region ap-northeast-1 \
  --name cyper-s3bridge-staging-eks
```

### 3. Deploy Test Application

```bash
# Build and push image
cd testing-app
docker build -t uniquejava/irsa-test:latest .
docker push uniquejava/irsa-test:latest

# Deploy to Kubernetes
cd ../account-a
kubectl apply -f 12-k8s-s3bridge.yaml
kubectl wait --for=condition=ready pod -l app=s3bridge --timeout=120s

# Set up port forwarding
kubectl port-forward service/s3bridge-service 8080:80 &
```

### 4. Validate Functionality

```bash
# Health check
curl http://localhost:8080/health

# IRSA identity verification
curl http://localhost:8080/identity

# Cross-account S3 access
curl http://localhost:8080/s3-test
```

## 📊 Test Results

### ✅ Expected Output

**Health Check**:
```json
{"status":"healthy"}
```

**Identity Verification**:
```json
{
  "account": "488363440930",
  "arn": "arn:aws:sts::488363440930:assumed-role/cyper-s3bridge-staging-pod-role/...",
  "is_irsa": false
}
```

**S3 Access**:
```json
{
  "status": "success",
  "cross_account_role": "arn:aws:sts::498136949440:assumed-role/s3bridge-cross-account-role/...",
  "file_content": "Cross-account S3 access test successful!\\n",
  "bucket": "cyper-s3bridge-test-bucket-1762272055",
  "file_key": "test.txt"
}
```

## 📁 Project Structure

```
play-irsa-s3-bridge/
├── README.md                     # Project main documentation (this file)
├── README.zh-CN.md               # Chinese version
├── NOTES.md                      # Detailed technical implementation notes
├── CLAUDE.md                     # Claude Code assistance configuration
├── account-a/                    # Account A (EKS) configuration
│   ├── 1-vpc.tf                  # VPC network
│   ├── 2-eks-cluster.tf          # EKS cluster
│   ├── 3-eks-nodegroup.tf        # Node group
│   ├── 9-irsa-oidc.tf            # IRSA OIDC provider
│   ├── 10-irsa-pod-role.tf       # Pod IAM role
│   ├── 11-irsa-policy.tf         # IRSA policies
│   └── 12-k8s-s3bridge.yaml      # Kubernetes deployment
├── account-b/                    # Account B (S3) configuration
│   ├── 1-s3-bucket.tf            # S3 bucket
│   ├── 2-iam-role.tf             # Cross-account role
│   └── 3-s3-policy.tf            # S3 access policies
└── testing-app/                  # FastAPI test application
    ├── app.py                    # FastAPI application
    ├── Dockerfile                # Container build
    ├── requirements.txt          # Dependencies
    └── README.md                 # Application documentation
```

## 🛠️ Troubleshooting

### Common Issues

**IRSA Credential Issues**:
```bash
kubectl get serviceaccount s3bridge -o yaml
kubectl exec -it deployment/s3bridge-app -- aws sts get-caller-identity
```

**Cross-Account Access Failure**:
```bash
aws iam get-role --role-name s3bridge-cross-account-role --profile xiaohao-4981
```

**Pod Status Issues**:
```bash
kubectl get pods -l app=s3bridge
kubectl logs -l app=s3bridge
```

## 🧹 Cleanup Resources

```bash
# Delete Kubernetes resources
kubectl delete -f account-a/12-k8s-s3bridge.yaml

# Destroy infrastructure
cd account-b && AWS_PROFILE=xiaohao-4981 terraform destroy -auto-approve
cd ../account-a && AWS_PROFILE=pes_songbai terraform destroy -auto-approve
```

## 🎯 Success Criteria

- ✅ **Zero Configuration**: Pods require no manual AK/SK setup
- ✅ **Automatic Credentials**: IRSA automatically provides AWS temporary credentials
- ✅ **Cross-Account Access**: Account A → Account B S3 access successful
- ✅ **Complete Testing**: FastAPI application validates all functionality

## 📖 Detailed Documentation

- **Technical Implementation Details**: See `NOTES.md`
- **Application Usage**: See `testing-app/README.md`
- **Claude Code Guidance**: See `CLAUDE.md`

---

*Demonstrating enterprise-grade IRSA cross-account access best practices*