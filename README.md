# EKS 跨账户 S3 访问实战：IRSA 架构设计

这个项目演示了如何通过 IAM Roles for Service Accounts (IRSA) 实现 EKS Pod 跨账户访问 S3 的完整方案。架构跨越两个 AWS 账户，展示了安全且成本优化的跨账户资源访问模式。

```shell
$ aws eks update-kubeconfig \
--region ap-northeast-1 \
--name cyper-s3bridge-staging-eks

$ k get nodes
NAME                                            STATUS   ROLES    AGE     VERSION
ip-10-0-20-38.ap-northeast-1.compute.internal   Ready    <none>   5m30s   v1.34.1-eks-113cf36

$ k auth can-i "*" "*"
yes

```

## 架构设计

```
┌─────────────────┐          ┌─────────────────┐
│   账户 A        │          │   账户 B        │
│  (EKS 账户)     │          │  (S3 账户)     │
├─────────────────┤          ├─────────────────┤
│                 │          │                 │
│  ┌───────────┐  │          │  ┌───────────┐  │
│  │EKS 集群   │  │ IRSA +   │  │ S3 存储桶 │  │
│  │           │  │跨账户   │  │           │  │
│  └─────┬─────┘  │ 角色扮演  │  └───────────┘  │
│        │        │   ───────▶│                 │
│  ┌─────▼─────┐  │          │  ┌───────────┐  │
│  │测试 Pod   │  │          │  │跨账户     │  │
│  │(带 IRSA)  │─┼──────────▶│  │S3 角色     │  │
│  └───────────┘  │          │  └───────────┘  │
│        │        │          │                 │
│  ┌─────▼─────┐  │          │                 │
│  │S3 VPC     │  │          │                 │
│  │网关端点   │◀─┼──────────┤                 │
│  │(Gateway)  │  │ 专线链路  │                 │
│  └───────────┘  │          │                 │
└─────────────────┘          └─────────────────┘
```

## 核心组件

### 账户 A (EKS 账户)
- **EKS 集群**: 启用 IRSA 功能的 Kubernetes 集群
- **VPC 设计**: 配置 S3 VPC 网关端点，实现私有网络 S3 访问
- **IAM 角色链**: Pod 角色具备跨账户角色扮演权限
- **状态管理**: 使用 S3 后端管理 Terraform 状态

### 账户 B (S3 账户)
- **S3 存储桶**: 用于跨账户访问的目标存储
- **跨账户角色**: 可被账户 A Pod 角色扮演的 IAM 角色
- **权限策略**: 精确控制 S3 访问权限
- **状态管理**: 独立的 Terraform 状态后端

### 安全特性
- **IRSA**: Pod 级别的 IAM 凭证，无需管理长期凭证
- **跨账户委托**: 通过 IAM 角色链实现安全的权限委托
- **网络隔离**: S3 流量通过 AWS 专网，避免公网暴露
- **最小权限原则**: 仅授予必要的 S3 操作权限

## 快速开始

### 环境配置

```bash
# 配置 AWS 账户信息
cp .env.example .env
# 编辑 .env 文件，填入实际的账户配置
```

环境变量配置：
```bash
# 账户 A (EKS 账户)
ACCOUNT_A_ID=488363440930
ACCOUNT_A_PROFILE=eks-account-profile

# 账户 B (S3 账户)
ACCOUNT_B_ID=498136949440
ACCOUNT_B_PROFILE=s3-account-profile

# AWS 区域配置
AWS_REGION=ap-northeast-1
CLUSTER_NAME=s3bridge-cluster
S3_BUCKET_NAME=s3bridge-demo-bucket-$(date +%s)
```

### 部署架构

**自动化部署（推荐）**：
```bash
./scripts/deploy.sh
```

一键部署脚本处理：
- Terraform 状态存储桶初始化
- 跨账户依赖关系解析
- EKS 集群与 IRSA 配置
- S3 存储桶与跨账户访问设置
- Kubernetes 配置更新
- 测试 Pod 部署与验证

### 验证部署

```bash
# 检查 Pod 身份
kubectl exec -it s3bridge-test-pod -- aws sts get-caller-identity

# 测试 S3 存储桶访问
kubectl exec -it s3bridge-test-pod -- aws s3 ls s3://$S3_BUCKET_NAME/

# 测试 S3 写入权限
kubectl exec -it s3bridge-test-pod -- sh -c "echo 'Cross-account access successful' > /tmp/test.txt"
kubectl exec -it s3bridge-test-pod -- aws s3 cp /tmp/test.txt s3://$S3_BUCKET_NAME/demo.txt

# 验证写入结果
kubectl exec -it s3bridge-test-pod -- aws s3 cp s3://$S3_BUCKET_NAME/demo.txt /tmp/verify.txt
kubectl exec -it s3bridge-test-pod -- cat /tmp/verify.txt
```

## 成本优化策略

### VPC S3 网关端点
- **成本节约**: 消除 NAT 网关费用，S3 访问不再产生公网流量成本
- **性能优化**: 流量保持在 AWS 专网内，延迟更低
- **安全增强**: 无需通过互联网网关，减少攻击面

### 基础设施规模
- **EKS 集群**: 2 台 t3.medium 实例（最小可用配置）
- **S3 存储**: 按需付费模式，存储和请求费用
- **VPC 端点**: 无小时费用，仅按数据处理量计费

## 关键技术点

### IAM 角色链设计
1. **Pod 角色**: EKS Pod 通过 IRSA 扮担 `s3bridge-cluster-pod-role`
2. **跨账户扮演**: Pod 角色进一步扮演账户 B 的 `s3bridge-cross-account-role`
3. **权限继承**: 跨账户角色继承目标 S3 存储桶的访问权限

### 网络架构优化
- **私有子网部署**: EKS 节点部署在私有子网中
- **专线访问**: S3 流量通过 AWS 专网，不经过互联网
- **端点配置**: Gateway 类型 VPC 端点，支持高吞吐量访问

## 架构目录

```
play-irsa-s3-bridge/
├── .env                         # AWS 账户配置文件
├── scripts/                     # 自动化部署脚本
│   ├── deploy.sh               # 完整部署自动化
│   ├── destroy.sh              # 资源清理自动化
│   ├── setup-state-buckets.sh  # Terraform 状态初始化
│   └── cleanup-state-buckets.sh # 状态存储清理
├── account-a/                   # EKS 账户配置
│   ├── main.tf                 # EKS、VPC、端点、IAM 角色定义
│   ├── variables.tf            # 输入变量配置
│   └── outputs.tf              # 输出变量定义
├── account-b/                   # S3 账户配置
│   ├── main.tf                 # S3 存储桶、跨账户 IAM 角色
│   ├── variables.tf            # 输入变量配置
│   └── outputs.tf              # 输出变量定义
├── k8s/                         # Kubernetes 资源定义
│   ├── test-pod.yaml          # ServiceAccount 与测试 Pod 模板
│   └── verify-scripts/
│       └── test-s3-access.sh  # 跨账户 S3 访问验证脚本
├── CLAUDE.md                   # Claude Code 辅助配置
├── NOTES.md                     # 技术问题解决笔记
└── README.md                   # 项目说明文档
```

## 最佳实践与故障排查

### 常见问题处理

**VPC CIDR 冲突检测**：
```bash
# 检查目标区域是否存在 CIDR 冲突
aws ec2 describe-vpcs --region $AWS_REGION \
  --query 'Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output table

# 冲突示例：
# | vpc-0123456789abcdef0 |  10.0.0.0/16    |
# | vpc-0fedcba9876543210 |  10.0.0.0/16    |  <- 冲突！
# | vpc-abcdef1234567890 |  192.168.0.0/16  |

# 解决方案：本项目使用 192.168.0.0/16 避免默认 CIDR 冲突
```

**节点组创建失败**：
- **症状**: `NodeCreationFailure: Unhealthy nodes in the kubernetes cluster`
- **根因**: VPC CIDR 冲突或 IAM 角色权限配置错误
- **解决方案**: 详见 `NOTES.md` 中的详细排查过程

**跨账户角色扮演失败**：
- 验证账户 B 的信任策略包含账户 A 的 Pod 角色 ARN
- 检查 Pod 角色是否具备 `sts:AssumeRole` 权限
- 确认跨账户角色的信任关系配置正确

### 架构验证命令

```bash
# 检查 Terraform 状态
terraform state list

# 验证 AWS 凭证配置
aws sts get-caller-identity

# 检查 Pod 运行状态
kubectl get pods -o wide

# 验证 ServiceAccount 配置
kubectl get serviceaccount s3bridge-app -o yaml

# 测试网络连通性
kubectl exec -it s3bridge-test-pod -- nc -zv s3.ap-northeast-1.amazonaws.com 443
```

## 清理资源

```bash
# 自动化清理
./scripts/destroy.sh

# 手动清理（如需精细控制）
kubectl delete -f k8s/test-pod-updated.yaml --ignore-not-found=true
cd account-a && terraform destroy -auto-approve
cd ../account-b && terraform destroy -auto-approve
```

---

*这个项目展示了企业级 AWS 跨账户访问的最佳实践，适合在生产环境中参考和定制化。*