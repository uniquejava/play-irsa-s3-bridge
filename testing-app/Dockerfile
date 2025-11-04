FROM python:3.11-slim

WORKDIR /app

# 使用阿里云镜像源加速pip安装
RUN pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/ && \
    pip config set install.trusted-host mirrors.aliyun.com

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]