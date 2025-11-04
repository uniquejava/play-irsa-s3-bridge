# EKS Pod 使用的 IAM 角色
# 这个角色将被 ServiceAccount "s3bridge-app" 使用

resource "aws_iam_role" "eks_pod_role" {
  name = "${local.prefix}-pod-role"

  # 使用 OIDC 身份验证策略
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_role_policy.json

  tags = local.tags
}

# Pod 角色的描述
resource "aws_iam_role_policy_attachment" "pod_role_description" {
  role       = aws_iam_role.eks_pod_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 输出 Pod 角色信息，供后续使用
# 这个 ARN 需要在 ServiceAccount 中使用
# 也需要在 Account B 中作为信任策略