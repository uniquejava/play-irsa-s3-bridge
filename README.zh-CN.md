# EKS 跨账户 S3 访问实战：IRSA 架构实现

通过 IAM Roles for Service Accounts (IRSA) 实现 EKS Pod 跨账户访问 S3 的完整方案，使用 FastAPI 应用验证功能。

[English](README.md) | 简体中文

## 🎯 项目状态

**✅ 实现完成** - IRSA 跨账户 S3 访问功能已完全实现并通过测试

- **Account A** (488363440930): EKS 集群 + IRSA 配置
- **Account B** (498136949440): S3 存储桶 + 跨账户角色
- **测试应用**: FastAPI 服务验证所有功能

## 🏗️ 架构概览

```
┌─────────────────┐          ┌─────────────────┐
│   账户 A        │          │   账户 B        │
│  (EKS 账户)     │          │  (S3 账户)     │
│  ┌───────────┐  │ IRSA +   │  ┌───────────┐  │
│  │EKS 集群   │  │跨账户   │  │ S3 存储桶 │  │
│  └─────┬─────┘  │ 角色扮演  │  └───────────┘  │
│        │        │   ───────▶│                 │
│  ┌─────▼─────┐  │          │  ┌───────────┐  │
│  │s3bridge   │  │          │  │跨账户     │  │
│  │FastAPI Pod│─┼──────────▶│  │S3 角色     │  │
│  └───────────┘  │          │  └───────────┘  │
└─────────────────┘          └─────────────────┘
```

## 🚀 快速部署

### 前置要求
- AWS CLI 配置好两个 profiles：
  - Account A (EKS): `pes_songbai`
  - Account B (S3): `xiaohao-4981`
- Docker 和 kubectl 已安装

### 1. 基础设施部署

```bash
# Account A - EKS 集群和 IRSA
cd account-a
terraform init
AWS_PROFILE=pes_songbai terraform apply -auto-approve \
  -var="aws_region=ap-northeast-1" \
  -var="cluster_name=cyper-s3bridge-staging-eks" \
  -var="s3_bucket_account_id=498136949440"

# Account B - S3 存储桶和跨账户角色
cd ../account-b
terraform init
AWS_PROFILE=xiaohao-4981 terraform apply -auto-approve \
  -var="aws_region=ap-northeast-1" \
  -var="s3_bucket_name=cyper-s3bridge-test-bucket-1762272055" \
  -var="eks_account_role_arn=$(cd ../account-a && AWS_PROFILE=pes_songbai terraform output -raw pod_role_arn)"
```

### 2. 配置 kubectl

```bash
AWS_PROFILE=pes_songbai aws eks update-kubeconfig \
  --region ap-northeast-1 \
  --name cyper-s3bridge-staging-eks
```

### 3. 部署测试应用

```bash
# 构建和推送镜像
cd testing-app
docker build -t uniquejava/irsa-test:latest .
docker push uniquejava/irsa-test:latest

# 部署到 Kubernetes
cd ../account-a
kubectl apply -f 12-k8s-s3bridge.yaml
kubectl wait --for=condition=ready pod -l app=s3bridge --timeout=120s

# 设置端口转发
kubectl port-forward service/s3bridge-service 8080:80 &
```

### 4. 验证功能

```bash
# 健康检查
curl http://localhost:8080/health

# IRSA 身份验证
curl http://localhost:8080/identity

# 跨账户 S3 访问
curl http://localhost:8080/s3-test
```

## 📊 测试结果

### ✅ 预期输出

**健康检查**：
```json
{"status":"healthy"}
```

**身份验证**：
```json
{
  "account": "488363440930",
  "arn": "arn:aws:sts::488363440930:assumed-role/cyper-s3bridge-staging-pod-role/...",
  "is_irsa": false
}
```

**S3 访问**：
```json
{
  "status": "success",
  "cross_account_role": "arn:aws:sts::498136949440:assumed-role/s3bridge-cross-account-role/...",
  "file_content": "Cross-account S3 access test successful!\\n",
  "bucket": "cyper-s3bridge-test-bucket-1762272055",
  "file_key": "test.txt"
}
```

## 📁 项目结构

```
play-irsa-s3-bridge/
├── README.md                     # 英文版本文档
├── README.zh-CN.md               # 中文版本文档（本文件）
├── NOTES.md                      # 详细技术实现笔记
├── CLAUDE.md                     # Claude Code 辅助配置
├── account-a/                    # Account A (EKS) 配置
│   ├── 1-vpc.tf                  # VPC 网络
│   ├── 2-eks-cluster.tf          # EKS 集群
│   ├── 3-eks-nodegroup.tf        # 节点组
│   ├── 9-irsa-oidc.tf            # IRSA OIDC 提供者
│   ├── 10-irsa-pod-role.tf       # Pod IAM 角色
│   ├── 11-irsa-policy.tf         # IRSA 策略
│   └── 12-k8s-s3bridge.yaml      # Kubernetes 部署
├── account-b/                    # Account B (S3) 配置
│   ├── 1-s3-bucket.tf            # S3 存储桶
│   ├── 2-iam-role.tf             # 跨账户角色
│   └── 3-s3-policy.tf            # S3 访问策略
└── testing-app/                  # FastAPI 测试应用
    ├── app.py                    # FastAPI 应用
    ├── Dockerfile                # 容器构建
    ├── requirements.txt          # 依赖
    └── README.md                 # 应用说明
```

## 🛠️ 故障排查

### 常见问题

**IRSA 凭证问题**：
```bash
kubectl get serviceaccount s3bridge -o yaml
kubectl exec -it deployment/s3bridge-app -- aws sts get-caller-identity
```

**跨账户访问失败**：
```bash
aws iam get-role --role-name s3bridge-cross-account-role --profile xiaohao-4981
```

**Pod 状态问题**：
```bash
kubectl get pods -l app=s3bridge
kubectl logs -l app=s3bridge
```

## 🧹 清理资源

```bash
# 删除 Kubernetes 资源
kubectl delete -f account-a/12-k8s-s3bridge.yaml

# 销毁基础设施
cd account-b && AWS_PROFILE=xiaohao-4981 terraform destroy -auto-approve
cd ../account-a && AWS_PROFILE=pes_songbai terraform destroy -auto-approve
```

## 🎯 成功标准

- ✅ **零配置**: Pod 无需手动 AK/SK 设置
- ✅ **自动凭证**: IRSA 自动提供 AWS 临时凭证
- ✅ **跨账户访问**: Account A → Account B 的 S3 访问成功
- ✅ **完整测试**: FastAPI 应用验证所有功能

## 📖 详细文档

- **技术实现细节**: 见 `NOTES.md`
- **应用使用说明**: 见 `testing-app/README.md`
- **Claude Code 指导**: 见 `CLAUDE.md`

---

*展示企业级 IRSA 跨账户访问的最佳实践*