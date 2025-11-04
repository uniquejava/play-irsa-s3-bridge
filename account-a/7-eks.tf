resource "aws_iam_role" "eks" {
  name = "${local.prefix}-eks-cluster"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
   {
     "Effect": "Allow",
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "eks.amazonaws.com"
     }
   }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks.name
}

# EKS Control Plane ( <=10 min )
resource "aws_eks_cluster" "eks" {
  name     = local.eks_name
  version = local.eks_version
  role_arn = aws_iam_role.eks.arn

  vpc_config {
    endpoint_private_access = false
    endpoint_public_access = true

    # 限制只允许特定 IP 段访问
    # cluster_endpoint_public_access_cidrs

    # subnet_ids
    # 控制平面 回连到你的 VPC 内部资源（如节点）时使用的源 IP（会从这些子网的 CIDR 中分配）
    # 如果启用了 private_access = true，AWS 会在这些子网中创建 ENI（弹性网络接口），用于提供私有 DNS 解析和私有 endpoint 访问。
    subnet_ids = [
      aws_subnet.private_zone1.id,
      aws_subnet.private_zone2.id
    ]
  }

  access_config {
    # can be old "CONFIG_MAP"
    authentication_mode = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks]
}

