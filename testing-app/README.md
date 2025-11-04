# IRSA FastAPI 测试应用

简洁的FastAPI应用，用于验证IRSA跨账户S3访问功能，无需任何手动AK/SK配置。

## 🎯 测试目标

验证EKS Pod通过IRSA自动获取AWS凭证，实现跨账户S3访问：
- ✅ IRSA自动凭证获取
- ✅ 跨账户角色扮演 (Account A → Account B)
- ✅ S3文件读取访问
- ✅ 零配置部署

## 🚀 快速开始

### 1. 构建和部署

```bash
# 构建Docker镜像（使用阿里云镜像源优化）
docker build -t uniquejava/irsa-test:latest .

# 推送到Docker Hub
docker push uniquejava/irsa-test:latest

# 部署到Kubernetes（使用主项目中的部署配置）
cd ../account-a
kubectl apply -f 12-k8s-s3bridge.yaml

# 等待Pod启动
kubectl wait --for=condition=ready pod -l app=s3bridge --timeout=120s

# 设置端口转发
kubectl port-forward service/s3bridge-service 8080:80 &
```

### 2. 测试API端点

```bash
# 1. 健康检查
curl http://localhost:8080/health

# 2. IRSA身份验证（显示Account A身份）
curl http://localhost:8080/identity

# 3. 跨账户S3访问（读取之前创建的test.txt文件）
curl http://localhost:8080/s3-test
```

## 📊 实际测试结果

### `/health` 端点 - 健康检查 ✅
```json
{"status":"healthy"}
```

### `/identity` 端点 - IRSA身份验证 ✅
```json
{
  "account": "488363440930",
  "arn": "arn:aws:sts::488363440930:assumed-role/cyper-s3bridge-staging-pod-role/botocore-session-1762276570",
  "is_irsa": false
}
```

### `/s3-test` 端点 - 跨账户S3访问 ✅
```json
{
  "status": "success",
  "cross_account_role": "arn:aws:sts::498136949440:assumed-role/s3bridge-cross-account-role/fastapi-test",
  "file_content": "Cross-account S3 access test successful!\\n",
  "bucket": "cyper-s3bridge-test-bucket-1762272055",
  "file_key": "test.txt"
}
```

## 🔍 API端点说明

| 端点 | 功能 | 验证内容 |
|------|------|----------|
| `GET /health` | 健康检查 | Pod运行状态和Kubernetes就绪性 |
| `GET /` | 应用信息 | 基础配置和目标存储桶信息 |
| `GET /identity` | 身份验证 | IRSA自动获取Account A身份 |
| `GET /s3-test` | S3访问测试 | 跨账户角色扮演 + 文件读取 |

## 🎯 成功标准

测试成功的标志：
- ✅ **健康检查通过** - Pod正常运行且就绪
- ✅ **Account A身份** - IRSA获取正确的EKS账户身份
- ✅ **跨账户角色成功** - 能扮演Account B的S3角色
- ✅ **文件读取成功** - 能读取S3中的test.txt文件
- ✅ **零配置** - 无需任何手动AK/SK设置

## 🚨 故障排查

### Pod无法启动
```bash
# 检查Pod状态和日志
kubectl get pods -l app=s3bridge
kubectl logs -l app=s3bridge

# 检查部署配置
kubectl describe deployment s3bridge-app
```

### IRSA凭证问题
```bash
# 检查ServiceAccount注解
kubectl get serviceaccount s3bridge -o yaml

# 验证IAM角色信任关系
aws iam get-role --role-name cyper-s3bridge-staging-pod-role

# 检查Pod环境变量
kubectl exec -it deployment/s3bridge-app -- env | grep AWS
```

### 跨账户访问失败
```bash
# 检查跨账户角色权限
aws iam get-role --role-name s3bridge-cross-account-role --profile xiaohao-4981

# 验证信任策略
aws iam get-role-policy --role-name s3bridge-cross-account-role --policy-name s3bridge-cross-account-policy --profile xiaohao-4981
```

### 网络连接问题
```bash
# 测试Pod网络连接
kubectl exec -it deployment/s3bridge-app -- curl -I https://sts.ap-northeast-1.amazonaws.com

# 测试S3连接
kubectl exec -it deployment/s3bridge-app -- nc -zv s3.ap-northeast-1.amazonaws.com 443
```

### 镜像拉取问题
```bash
# 检查镜像拉取状态
kubectl describe pod -l app=s3bridge

# 强制重新拉取镜像
kubectl patch deployment s3bridge-app -p '{"spec":{"template":{"spec":{"containers":[{"name":"s3bridge-container","imagePullPolicy":"Always"}]}}}}'
```

## 🧹 清理资源

```bash
# 删除Kubernetes资源
kubectl delete -f ../account-a/12-k8s-s3bridge.yaml

# 删除Docker镜像（可选）
docker rmi uniquejava/irsa-test:latest
```

## 📁 文件说明

- `app.py` - FastAPI应用主文件，包含三个测试端点
- `requirements.txt` - Python依赖包（fastapi, uvicorn, boto3）
- `Dockerfile` - 容器构建配置（阿里云镜像源优化）
- `README.md` - 本文档

## 🐳 Docker优化

Docker构建使用以下优化策略：

1. **阿里云镜像源**：使用阿里云PyPI镜像加速pip安装
2. **缓存优化**：合理利用Docker层缓存，仅复制变更文件
3. **最小镜像**：基于python:3.11-slim，减少镜像大小

```dockerfile
# 使用阿里云镜像源加速pip安装
RUN pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/ && \
    pip config set install.trusted-host mirrors.aliyun.com
```

## 🔗 相关资源

- **主项目文档**: `../README.md` - 完整的架构设计和部署指南
- **技术实现笔记**: `../NOTES.md` - 详细的实现过程和问题解决
- **Account A配置**: `../account-a/` - EKS集群和IRSA配置
- **Account B配置**: `../account-b/` - S3存储桶和跨账户角色
- **Kubernetes部署**: `../account-a/12-k8s-s3bridge.yaml` - 生产就绪的部署配置

## 🎯 测试验证

应用验证以下核心功能：

1. **IRSA自动凭证管理** - Pod启动时自动获取AWS临时凭证
2. **跨账户身份链路** - Account A → Account B的安全角色扮演
3. **S3资源访问** - 读取跨账户S3存储桶中的文件
4. **健康监控** - Kubernetes集成的健康检查端点

---

*此应用专门用于验证IRSA跨账户S3访问功能，已通过完整测试验证。*