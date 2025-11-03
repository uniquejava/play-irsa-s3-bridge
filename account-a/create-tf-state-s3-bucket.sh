export AWS_PROFILE=pes_songbai
aws s3 mb s3://cyper-s3bridge-tf-state-account-a --region ap-northeast-1
aws s3api put-bucket-versioning \
    --bucket cyper-s3bridge-tf-state-account-a \
    --versioning-configuration Status=Enabled