#!/usr/bin/env python3
"""
简洁的IRSA跨账户S3访问测试 - FastAPI版本
"""

import boto3
import os
from fastapi import FastAPI, HTTPException

app = FastAPI(title="IRSA S3 Test", version="1.0")

@app.get("/health")
async def health_check():
    """健康检查端点"""
    return {"status": "healthy"}

# 配置
CROSS_ACCOUNT_ROLE = "arn:aws:iam::498136949440:role/s3bridge-cross-account-role"
BUCKET_NAME = "cyper-s3bridge-test-bucket-1762272055"
TEST_FILE_KEY = "test.txt"  # 之前创建的文件

def get_s3_client():
    """获取跨账户S3客户端"""
    sts = boto3.client('sts')
    response = sts.assume_role(
        RoleArn=CROSS_ACCOUNT_ROLE,
        RoleSessionName="fastapi-test"
    )

    return boto3.client(
        's3',
        aws_access_key_id=response['Credentials']['AccessKeyId'],
        aws_secret_access_key=response['Credentials']['SecretAccessKey'],
        aws_session_token=response['Credentials']['SessionToken']
    ), response

@app.get("/")
async def root():
    return {
        "service": "IRSA Cross-Account S3 Test",
        "bucket": BUCKET_NAME
    }

@app.get("/identity")
async def get_identity():
    """获取当前AWS身份"""
    sts = boto3.client('sts')
    identity = sts.get_caller_identity()
    return {
        "account": identity['Account'],
        "arn": identity['Arn'],
        "is_irsa": "AssumedRole" in identity['Arn']
    }

@app.get("/s3-test")
async def test_s3():
    """测试读取之前创建的S3文件"""
    try:
        s3, role_response = get_s3_client()

        # 读取文件
        obj = s3.get_object(Bucket=BUCKET_NAME, Key=TEST_FILE_KEY)
        content = obj['Body'].read().decode('utf-8')

        return {
            "status": "success",
            "cross_account_role": role_response['AssumedRoleUser']['Arn'],
            "file_content": content,
            "bucket": BUCKET_NAME,
            "file_key": TEST_FILE_KEY
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)