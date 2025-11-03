#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting S3 Bridge MVP Deployment${NC}"

# Load environment variables
if [ -f .env ]; then
    source .env
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}❌ .env file not found!${NC}"
    exit 1
fi

# Generate unique bucket name if not set
if [ -z "$S3_BUCKET_NAME" ] || [[ "$S3_BUCKET_NAME" == *"$(date +%s)"* ]]; then
    export S3_BUCKET_NAME="s3bridge-demo-bucket-$(date +%s)"
    echo -e "${YELLOW}📝 Generated unique S3 bucket name: ${S3_BUCKET_NAME}${NC}"
fi

echo -e "${BLUE}📊 Deployment Configuration:${NC}"
echo -e "  Account A (EKS): ${ACCOUNT_A_ID} (${ACCOUNT_A_PROFILE})"
echo -e "  Account B (S3):  ${ACCOUNT_B_ID} (${ACCOUNT_B_PROFILE})"
echo -e "  Region:          ${AWS_REGION}"
echo -e "  Cluster:         ${CLUSTER_NAME}"
echo -e "  S3 Bucket:       ${S3_BUCKET_NAME}"
echo ""


# Function to initialize Account B Terraform
init_account_b() {
    echo -e "${YELLOW}🔧 Initializing Account B Terraform...${NC}"
    cd account-b
    AWS_PROFILE=$ACCOUNT_B_PROFILE terraform init
    cd ..
    echo -e "${GREEN}✓ Account B Terraform initialized${NC}"
}

# Function to deploy to account A (EKS)
deploy_account_a() {
    echo -e "${YELLOW}🏗️  Deploying Account A (EKS Cluster)...${NC}"
    cd account-a

    # Initialize Terraform
    AWS_PROFILE=$ACCOUNT_A_PROFILE terraform init

    # Apply Terraform
    AWS_PROFILE=$ACCOUNT_A_PROFILE terraform apply \
        -var="aws_region=${AWS_REGION}" \
        -var="cluster_name=${CLUSTER_NAME}" \
        -var="s3_bucket_account_id=${ACCOUNT_B_ID}" \
        -auto-approve

    cd ..
    echo -e "${GREEN}✓ Account A deployed successfully${NC}"
}

# Function to get outputs
get_outputs() {
    echo -e "${BLUE}📤 Getting Terraform Outputs...${NC}"

    # Get Account A outputs
    cd account-a
    POD_ROLE_ARN=$(AWS_PROFILE=$ACCOUNT_A_PROFILE terraform output -raw pod_role_arn)
    CLUSTER_NAME_OUTPUT=$(AWS_PROFILE=$ACCOUNT_A_PROFILE terraform output -raw cluster_name)
    cd ..

    echo -e "${GREEN}✓ Pod Role ARN: ${POD_ROLE_ARN}${NC}"
    echo -e "${GREEN}✓ Cluster Name: ${CLUSTER_NAME_OUTPUT}${NC}"

    # Export for other scripts
    export POD_ROLE_ARN
    export CLUSTER_NAME_OUTPUT
}

# Function to update Kubernetes config
update_k8s_config() {
    echo -e "${YELLOW}☸️  Updating Kubernetes configuration...${NC}"
    AWS_PROFILE=$ACCOUNT_A_PROFILE aws eks update-kubeconfig \
        --region ${AWS_REGION} \
        --name ${CLUSTER_NAME_OUTPUT}
    echo -e "${GREEN}✓ kubectl configured for cluster: ${CLUSTER_NAME_OUTPUT}${NC}"
}

# Function to deploy test pod
deploy_test_pod() {
    echo -e "${YELLOW}🚀 Deploying test pod...${NC}"

    # Update the pod YAML with the correct role ARN
    sed "s/<ACCOUNT_A_POD_ROLE_ARN>/${POD_ROLE_ARN}/g" k8s/test-pod.yaml > k8s/test-pod-updated.yaml

    # Apply the updated pod configuration
    kubectl apply -f k8s/test-pod-updated.yaml

    echo -e "${GREEN}✓ Test pod deployed${NC}"
}

# Function to test S3 access
test_s3_access() {
    echo -e "${YELLOW}🧪 Testing S3 cross-account access...${NC}"

    # Wait for pod to be ready
    echo -e "${YELLOW}⏳ Waiting for pod to be ready...${NC}"
    kubectl wait --for=condition=Ready pod/s3bridge-test-pod --timeout=300s

    # Run the verification script
    export S3_BUCKET_NAME
    bash k8s/verify-scripts/test-s3-access.sh

    echo -e "${GREEN}✓ S3 access test completed${NC}"
}

# Function to cleanup test resources
cleanup() {
    echo -e "${YELLOW}🧹 Cleaning up test resources...${NC}"

    # Delete test pod
    kubectl delete -f k8s/test-pod-updated.yaml 2>/dev/null || true
    rm -f k8s/test-pod-updated.yaml

    echo -e "${GREEN}✓ Test resources cleaned up${NC}"
}

# Main deployment flow
main() {
    trap cleanup EXIT

    echo -e "${BLUE}🚀 Starting MVP Deployment Flow${NC}"

    # Step 0: Ensure Terraform state buckets exist
    echo -e "${BLUE}Step 0: Setting up Terraform state buckets${NC}"
    bash scripts/setup-state-buckets.sh

    echo -e "${BLUE}Step 1: Deploying Account A (EKS) first to get pod role ARN${NC}"

    # Step 1: Initialize Account B Terraform (can be done in parallel)
    init_account_b

    # Step 2: Deploy Account A first (EKS) to get pod role ARN
    deploy_account_a

    # Step 3: Get outputs from Account A
    get_outputs

    # Step 4: Now deploy Account B with the pod role ARN
    echo -e "${BLUE}Step 2: Deploying Account B (S3) with pod role ARN${NC}"
    cd account-b
    AWS_PROFILE=$ACCOUNT_B_PROFILE terraform apply \
        -var="aws_region=${AWS_REGION}" \
        -var="s3_bucket_name=${S3_BUCKET_NAME}" \
        -var="eks_account_role_arn=${POD_ROLE_ARN}" \
        -auto-approve
    cd ..

    # Step 5: Update kubectl config
    echo -e "${BLUE}Step 3: Configuring Kubernetes access${NC}"
    update_k8s_config

    # Step 6: Deploy test pod
    echo -e "${BLUE}Step 4: Deploying test pod with IRSA configuration${NC}"
    deploy_test_pod

    # Step 7: Test S3 access
    echo -e "${BLUE}Step 5: Testing cross-account S3 access${NC}"
    test_s3_access

    echo -e "${GREEN}🎉 MVP Deployment completed successfully!${NC}"
    echo -e "${BLUE}📝 Summary:${NC}"
    echo -e "  • EKS Cluster: ${CLUSTER_NAME_OUTPUT}"
    echo -e "  • S3 Bucket: ${S3_BUCKET_NAME}"
    echo -e "  • Pod Role: ${POD_ROLE_ARN}"
    echo -e ""
    echo -e "${YELLOW}💡 To clean up, run: ./scripts/destroy.sh${NC}"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi