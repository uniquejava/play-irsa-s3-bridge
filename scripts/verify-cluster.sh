#!/bin/bash

# EKS Cluster Verification Script for s3bridge-cluster-v3
# This script verifies cluster health and prepares for cross-account S3 testing

set -e

CLUSTER_NAME="s3bridge-cluster-v3"
REGION="ap-northeast-1"
ACCOUNT_A_PROFILE="pes_songbai"

echo "🔍 EKS Cluster Verification Script"
echo "=================================="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Profile: $ACCOUNT_A_PROFILE"
echo ""

# Step 1: Configure kubectl
echo "Step 1: Configuring kubectl..."
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME --profile $ACCOUNT_A_PROFILE

# Step 2: Check cluster status
echo ""
echo "Step 2: Checking cluster status..."
aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile $ACCOUNT_A_PROFILE --query 'cluster.{Status:status,Version:version,Endpoint:endpoint}' --output table

# Step 3: Check node group status
echo ""
echo "Step 3: Checking node group status..."
NODEGROUP_NAME=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION --profile $ACCOUNT_A_PROFILE --query 'nodegroups[0]' --output text 2>/dev/null || echo "")

if [ -n "$NODEGROUP_NAME" ]; then
    echo "Node group found: $NODEGROUP_NAME"
    aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --profile $ACCOUNT_A_PROFILE --query 'nodegroup.{Status:status,Health:health,Scaling:scaling}' --output table
else
    echo "❌ No node groups found yet"
fi

# Step 4: Check kubectl connectivity
echo ""
echo "Step 4: Testing kubectl connectivity..."
kubectl cluster-info --request-timeout=10 || echo "⚠️  kubectl connectivity test failed"

# Step 5: Check nodes
echo ""
echo "Step 5: Checking node status..."
kubectl get nodes --show-labels || echo "⚠️  No nodes available yet"

# Step 6: Check system pods
echo ""
echo "Step 6: Checking system pods..."
kubectl get pods -n kube-system || echo "⚠️  Cannot list system pods yet"

# Step 7: Check IAM roles and IRSA setup
echo ""
echo "Step 7: Checking IRSA setup..."
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile $ACCOUNT_A_PROFILE --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null || echo "")
if [ -n "$OIDC_PROVIDER" ]; then
    echo "✅ OIDC Provider: $OIDC_PROVIDER"

    # Check for IAM role
    POD_ROLE=$(aws iam list-roles --query 'Roles[?contains(RoleName, `s3bridge-cluster-v3-pod-role`)].Arn' --output text --profile $ACCOUNT_A_PROFILE 2>/dev/null || echo "")
    if [ -n "$POD_ROLE" ]; then
        echo "✅ Pod IAM Role: $POD_ROLE"
    else
        echo "❌ Pod IAM Role not found"
    fi
else
    echo "❌ OIDC Provider not found"
fi

# Step 8: readiness assessment
echo ""
echo "Step 8: Readiness Assessment"
echo "============================"

CLUSTER_STATUS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile $ACCOUNT_A_PROFILE --query 'cluster.status' --output text 2>/dev/null || echo "UNKNOWN")
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")

echo "Cluster Status: $CLUSTER_STATUS"
echo "Ready Nodes: $NODE_COUNT"

if [ "$CLUSTER_STATUS" = "ACTIVE" ] && [ "$NODE_COUNT" -gt 0 ]; then
    echo "🎉 Cluster is ready for workloads!"
    echo ""
    echo "Next steps:"
    echo "1. Deploy test pod with IRSA configuration"
    echo "2. Deploy Account B S3 resources"
    echo "3. Test cross-account S3 access"
    exit 0
else
    echo "⏳ Cluster is still provisioning..."
    echo "Expected timeline:"
    echo "- EKS Cluster: 5-10 minutes"
    echo "- Node Group: 10-15 minutes"
    echo "- Node Bootstrap: 5-10 minutes"
    exit 1
fi