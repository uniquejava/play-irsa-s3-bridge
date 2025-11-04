export AWS_PROFILE=xiaohao-4981
aws s3 mb s3://cyper-s3bridge-tf-state-account-b --region ap-northeast-1
aws s3api put-bucket-versioning \
    --bucket cyper-s3bridge-tf-state-account-b \
    --versioning-configuration Status=Enabled