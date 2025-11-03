#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧹 Destroying S3 Bridge MVP Infrastructure${NC}"

# Load environment variables
if [ -f .env ]; then
    source .env
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}❌ .env file not found!${NC}"
    exit 1
fi

echo -e "${BLUE}📊 Cleanup Configuration:${NC}"
echo -e "  Account A (EKS): ${ACCOUNT_A_ID} (${ACCOUNT_A_PROFILE})"
echo -e "  Account B (S3):  ${ACCOUNT_B_ID} (${ACCOUNT_B_PROFILE})"
echo -e "  Region:          ${AWS_REGION}"
echo ""

# Function to destroy Kubernetes resources
destroy_k8s_resources() {
    echo -e "${YELLOW}☸️  Cleaning up Kubernetes resources...${NC}"

    # Check if cluster exists
    if AWS_PROFILE=$ACCOUNT_A_PROFILE aws eks describe-cluster \
        --name ${CLUSTER_NAME:-s3bridge-cluster} \
        --region ${AWS_REGION} >/dev/null 2>&1; then

        # Update kubectl config
        AWS_PROFILE=$ACCOUNT_A_PROFILE aws eks update-kubeconfig \
            --region ${AWS_REGION} \
            --name ${CLUSTER_NAME:-s3bridge-cluster} >/dev/null 2>&1 || true

        # Delete test pod if it exists
        kubectl delete pod s3bridge-test-pod --ignore-not-found=true
        kubectl delete serviceaccount s3bridge-app --ignore-not-found=true

        echo -e "${GREEN}✓ Kubernetes resources cleaned up${NC}"
    else
        echo -e "${YELLOW}⚠️  EKS cluster not found, skipping Kubernetes cleanup${NC}"
    fi
}

# Function to destroy Account A resources
destroy_account_a() {
    echo -e "${YELLOW}🏗️  Destroying Account A (EKS Cluster)...${NC}"
    cd account-a

    # Initialize if not already done
    if [ ! -d ".terraform" ]; then
        AWS_PROFILE=$ACCOUNT_A_PROFILE terraform init
    fi

    # Destroy resources
    AWS_PROFILE=$ACCOUNT_A_PROFILE terraform destroy \
        -var="aws_region=${AWS_REGION}" \
        -var="cluster_name=${CLUSTER_NAME:-s3bridge-cluster}" \
        -var="s3_bucket_account_id=${ACCOUNT_B_ID}" \
        -auto-approve

    cd ..
    echo -e "${GREEN}✓ Account A resources destroyed${NC}"
}

# Function to destroy Account B resources
destroy_account_b() {
    echo -e "${YELLOW}🏗️  Destroying Account B (S3 Bucket)...${NC}"
    cd account-b

    # Initialize if not already done
    if [ ! -d ".terraform" ]; then
        AWS_PROFILE=$ACCOUNT_B_PROFILE terraform init
    fi

    # Destroy resources
    AWS_PROFILE=$ACCOUNT_B_PROFILE terraform destroy \
        -var="aws_region=${AWS_REGION}" \
        -var="s3_bucket_name=${S3_BUCKET_NAME:-s3bridge-demo-bucket}" \
        -var="eks_account_role_arn=arn:aws:iam::${ACCOUNT_A_ID}:role/s3bridge-cluster-pod-role" \
        -auto-approve

    cd ..
    echo -e "${GREEN}✓ Account B resources destroyed${NC}"
}

# Function to clean up local files
cleanup_local_files() {
    echo -e "${YELLOW}🗑️  Cleaning up local files...${NC}"

    # Remove temporary files
    rm -f k8s/test-pod-updated.yaml

    # Remove terraform state files if they exist
    find . -name "*.terraform.lock.hcl" -delete 2>/dev/null || true
    find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true

    echo -e "${GREEN}✓ Local files cleaned up${NC}"
}

# Function to clean up state buckets (optional)
cleanup_state_buckets() {
    echo -e "${YELLOW}🪣 Cleaning up Terraform state buckets...${NC}"

    read -p "Do you want to delete Terraform state buckets? This cannot be undone. (type 'yes' to confirm): " confirm
    if [ "$confirm" = "yes" ]; then
        bash scripts/cleanup-state-buckets.sh
    else
        echo -e "${YELLOW}⚠️  State buckets left intact. You can clean them up later with: ./scripts/cleanup-state-buckets.sh${NC}"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo -e "${RED}⚠️  WARNING: This will destroy all infrastructure resources!${NC}"
    echo -e "${RED}   This action cannot be undone.${NC}"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm

    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}✅ Destruction cancelled.${NC}"
        exit 0
    fi
}

# Main destruction flow
main() {
    # Confirm destruction
    confirm_destruction

    # Step 1: Clean up Kubernetes resources
    destroy_k8s_resources

    # Step 2: Destroy Account A resources (EKS)
    destroy_account_a

    # Step 3: Destroy Account B resources (S3)
    destroy_account_b

    # Step 4: Clean up local files
    cleanup_local_files

    # Step 5: Optionally clean up state buckets
    cleanup_state_buckets

    echo -e "${GREEN}🎉 All resources destroyed successfully!${NC}"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi