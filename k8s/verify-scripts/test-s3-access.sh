#!/bin/bash
echo "🔍 Testing S3 cross-account access..."

# 获取当前身份
echo "📝 Current identity:"
kubectl exec -it s3bridge-test-pod -- aws sts get-caller-identity

# 测试S3访问
echo "🪣 Testing S3 bucket access..."
kubectl exec -it s3bridge-test-pod -- aws s3 ls s3://${S3_BUCKET_NAME}/ || echo "❌ S3 access failed"

# 测试S3写入
echo "📤 Testing S3 write access..."
kubectl exec -it s3bridge-test-pod -- sh -c "echo 'Hello from S3Bridge Pod' > /tmp/test.txt"
kubectl exec -it s3bridge-test-pod -- aws s3 cp /tmp/test.txt s3://${S3_BUCKET_NAME}/test-pod-access.txt

# 验证写入
echo "📥 Verifying S3 read access..."
kubectl exec -it s3bridge-test-pod -- aws s3 cp s3://${S3_BUCKET_NAME}/test-pod-access.txt /tmp/verify.txt
kubectl exec -it s3bridge-test-pod -- cat /tmp/verify.txt

echo "✅ Test completed!"