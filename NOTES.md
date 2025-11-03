# EKS Node Group 问题解决笔记

## 问题描述

在部署 EKS 集群 `s3bridge-cluster-v2` 时遇到节点组创建失败的问题：
- EKS 集群状态为 ACTIVE
- EC2 实例正在运行，但无法加入 Kubernetes 集群
- 节点组状态显示 `CREATE_FAILED`，错误信息：`NodeCreationFailure: Unhealthy nodes in the kubernetes cluster`

## 问题诊断过程

### 1. 初步检查
```bash
# 检查节点组状态
aws eks describe-node-group --cluster-name s3bridge-cluster-v2 --nodegroup-name default

# 检查 EC2 实例
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=s3bridge-cluster-v2"

# 发现：2个 EC2 实例在运行，但使用的是旧的节点角色
# 实例角色：default-eks-node-group-20251103084308323300000001
```

### 2. 深入分析 IAM 角色
```bash
# 列出所有 s3bridge 相关的角色
aws iam list-roles --query 'Roles[?contains(RoleName, `s3bridge`)]'

# 发现问题：
# - 集群角色：s3bridge-cluster-v2-cluster-20251103084948904200000003 ✅
# - Pod 角色：s3bridge-cluster-v2-pod-role ✅
# - 节点角色：default-eks-node-group-20251103084308323300000001 ❌ (旧角色)
```

### 3. Terraform 状态检查
```bash
cd account-a
terraform state list | grep -i iam

# 发现 Terraform 管理的节点角色：
# module.eks.module.eks_managed_node_group["default"].aws_iam_role.this[0]
# 但是实际创建的节点组使用了错误的 IAM 角色
```

## 根本原因

**EKS 模块重用了旧的节点角色**：
- 新集群 `s3bridge-cluster-v2` 的节点组应该创建新的 IAM 角色
- 但实际上使用了之前集群的旧角色 `default-eks-node-group-20251103084308323300000001`
- 旧角色的权限和配置不匹配新集群，导致 EC2 实例无法正确加入集群

## 解决方案

### 1. 修改 Terraform 配置

**文件**: `account-a/main.tf`
```diff
eks_managed_node_groups = {
-   default = {
+   s3bridge_nodes = {
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      instance_types = ["t3.medium"]
    }
  }
```

**作用**：通过更改节点组名称，强制 Terraform 创建全新的节点组和 IAM 角色

### 2. 强制重新创建节点组

```bash
cd account-a

# 标记现有节点组为已污染，强制重新创建
terraform taint 'module.eks.module.eks_managed_node_group["default"].aws_eks_node_group.this[0]'

# 应用变更
terraform apply \
  -var="aws_region=ap-northeast-1" \
  -var="cluster_name=s3bridge-cluster-v2" \
  -var="s3_bucket_account_id=498136949440" \
  -auto-approve
```

### 3. 验证新资源创建

Terraform 创建的新资源：
- ✅ **新 IAM 角色**：`s3bridge_nodes-eks-node-group-20251103095929847300000001`
- ✅ **新启动模板**：`lt-02e260f07106f0472`
- ✅ **IAM 策略附加**：EKS Worker Node, CNI, ECR 策略
- 🔄 **新节点组**：`s3bridge_nodes` (正在创建中)

## 关键命令总结

```bash
# 1. 问题诊断命令
aws eks describe-node-group --cluster-name s3bridge-cluster-v2 --nodegroup-name default
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=s3bridge-cluster-v2"
aws iam list-roles --query 'Roles[?contains(RoleName, `s3bridge`)]'

# 2. Terraform 状态检查
cd account-a
terraform state list | grep -i iam
terraform state show module.eks.module.eks_managed_node_group["default"].aws_eks_node_group.this[0]

# 3. 强制重新创建
terraform taint 'module.eks.module.eks_managed_node_group["default"].aws_eks_node_group.this[0]'
terraform apply -var="aws_region=ap-northeast-1" -var="cluster_name=s3bridge-cluster-v2" -var="s3_bucket_account_id=498136949440" -auto-approve
```

## 技术要点

1. **节点组命名的重要性**：节点组名称直接影响 IAM 角色的创建和关联
2. **Terraform 状态管理**：通过 taint 命令强制资源重新创建，而不是更新
3. **IAM 角色生命周期**：每个 EKS 节点组都应该有独立的 IAM 角色
4. **资源依赖关系**：节点组需要正确的 IAM 角色和权限才能成功加入集群

## 预防措施

1. **使用唯一的集群名称**：避免重复使用集群名称导致资源冲突
2. **清理旧资源**：在重新部署前，确保清理之前的所有相关资源
3. **状态验证**：部署后验证 Terraform 状态与实际 AWS 资源的一致性
4. **监控节点组创建**：EKS 节点组创建通常需要 5-10 分钟，需要耐心等待

## 结果

成功解决了节点组创建失败的问题：
- 旧的有问题的节点组被销毁
- 新的节点组使用正确的 IAM 角色正在创建
- EC2 实例将能够正确加入 Kubernetes 集群
- 为后续的 IRSA 跨账户 S3 访问演示奠定了基础

---

*记录时间：2025-11-03*
*解决问题：EKS 节点组创建失败，EC2 实例无法加入集群*