#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🗑️  Cleaning up Terraform State Buckets${NC}"

# Load environment variables
if [ -f .env ]; then
    source .env
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}❌ .env file not found!${NC}"
    exit 1
fi

# Function to delete state bucket
delete_state_bucket() {
    local profile=$1
    local bucket_name=$2
    local account_id=$3

    echo -e "${YELLOW}🗑️  Deleting state bucket ${bucket_name} from account ${account_id}${NC}"

    # Check if bucket exists
    if ! AWS_PROFILE=$profile aws s3api head-bucket --bucket ${bucket_name} 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Bucket ${bucket_name} does not exist${NC}"
        return 0
    fi

    # Delete all versions and delete markers
    echo -e "${YELLOW}📦 Emptying bucket ${bucket_name}...${NC}"

    # List and delete all versions
    AWS_PROFILE=$profile aws s3api list-object-versions --bucket ${bucket_name} --query 'Versions[?Key].{Key:Key,VersionId:VersionId}' --output text | \
    while read -r key version_id; do
        if [ -n "$key" ] && [ -n "$version_id" ]; then
            echo "  Deleting version: $key ($version_id)"
            AWS_PROFILE=$profile aws s3api delete-object --bucket ${bucket_name} --key "$key" --version-id "$version_id" || true
        fi
    done

    # List and delete all delete markers
    AWS_PROFILE=$profile aws s3api list-object-versions --bucket ${bucket_name} --query 'DeleteMarkers[?Key].{Key:Key,VersionId:VersionId}' --output text | \
    while read -r key version_id; do
        if [ -n "$key" ] && [ -n "$version_id" ]; then
            echo "  Deleting marker: $key ($version_id)"
            AWS_PROFILE=$profile aws s3api delete-object --bucket ${bucket_name} --key "$key" --version-id "$version_id" || true
        fi
    done

    # Delete the bucket
    echo -e "${YELLOW}🗑️  Deleting bucket ${bucket_name}...${NC}"
    AWS_PROFILE=$profile aws s3api delete-bucket --bucket ${bucket_name} || true

    echo -e "${GREEN}✓ State bucket ${bucket_name} deleted successfully${NC}"
}

# Confirm deletion
echo -e "${RED}⚠️  WARNING: This will delete Terraform state buckets and all their contents!${NC}"
echo -e "${RED}   This action cannot be undone and may affect your ability to manage existing infrastructure.${NC}"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}✅ State bucket cleanup cancelled.${NC}"
    exit 0
fi

# Delete state buckets for both accounts
echo -e "${BLUE}Deleting Terraform state buckets...${NC}"
delete_state_bucket $ACCOUNT_A_PROFILE "s3bridge-tf-state-account-a" $ACCOUNT_A_ID
delete_state_bucket $ACCOUNT_B_PROFILE "s3bridge-tf-state-account-b" $ACCOUNT_B_ID

echo -e "${GREEN}🎉 Terraform state buckets cleanup completed!${NC}"