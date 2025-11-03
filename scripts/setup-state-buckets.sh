#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🪣 Setting up Terraform State Buckets${NC}"

# Load environment variables
if [ -f .env ]; then
    source .env
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}❌ .env file not found!${NC}"
    exit 1
fi

# Function to create state bucket
create_state_bucket() {
    local profile=$1
    local bucket_name=$2
    local account_id=$3

    echo -e "${YELLOW}🪣 Creating state bucket ${bucket_name} in account ${account_id}${NC}"

    # Check if bucket already exists
    if AWS_PROFILE=$profile aws s3api head-bucket --bucket ${bucket_name} 2>/dev/null; then
        echo -e "${GREEN}✓ Bucket ${bucket_name} already exists${NC}"
        return 0
    fi

    # Create bucket with appropriate region
    local region_option="--region ${AWS_REGION}"
    if [ "$AWS_REGION" != "us-east-1" ]; then
        region_option="--region ${AWS_REGION} --create-bucket-configuration LocationConstraint=${AWS_REGION}"
    else
        region_option="--region ${AWS_REGION}"
    fi

    AWS_PROFILE=$profile aws s3api create-bucket \
        --bucket ${bucket_name} \
        $region_option

    # Enable versioning
    AWS_PROFILE=$profile aws s3api put-bucket-versioning \
        --bucket ${bucket_name} \
        --versioning-configuration Status=Enabled

    # Enable encryption
    AWS_PROFILE=$profile aws s3api put-bucket-encryption \
        --bucket ${bucket_name} \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'

    # Block public access
    AWS_PROFILE=$profile aws s3api put-public-access-block \
        --bucket ${bucket_name} \
        --public-access-block-configuration "BlockPublicAcls=true,BlockPublicPolicy=true,IgnorePublicAcls=true,RestrictPublicBuckets=true"

    echo -e "${GREEN}✓ State bucket ${bucket_name} created successfully${NC}"
}

# Create state buckets for both accounts
echo -e "${BLUE}Creating Terraform state buckets...${NC}"
create_state_bucket $ACCOUNT_A_PROFILE "s3bridge-tf-state-account-a" $ACCOUNT_A_ID
create_state_bucket $ACCOUNT_B_PROFILE "s3bridge-tf-state-account-b" $ACCOUNT_B_ID

echo -e "${GREEN}🎉 Terraform state buckets setup completed!${NC}"
echo -e "${YELLOW}💡 You can now run ./scripts/deploy.sh${NC}"