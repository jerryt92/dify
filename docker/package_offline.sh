#!/bin/bash

# 1. 获取 docker-compose 需要的所有镜像列表
echo "🔍 正在读取镜像列表..."
IMAGES=$(docker compose config --images)

if [ -z "$IMAGES" ]; then
    echo "❌ 错误：未能读取到镜像列表，请确保当前目录下有 docker-compose.yml"
    exit 1
fi

echo "📋 需要打包的镜像清单："
echo "$IMAGES"
echo "----------------------------------------"

# 2. 逐个拉取 x86_64 (AMD64) 架构的镜像
# 注意：这是为了确保离线服务器（Linux）能用
echo "⬇️  开始拉取 linux/amd64 架构镜像..."
for img in $IMAGES; do
    echo "   正在拉取: $img"
    docker pull --platform linux/amd64 "$img"
    
    if [ $? -ne 0 ]; then
        echo "❌ 拉取失败: $img"
        exit 1
    fi
done

# 3. 执行打包
echo "📦 正在打包所有镜像为 bisheng_offline.tar ..."
# 将换行符转换为空格，传递给 docker save
IMG_LINE=$(echo $IMAGES | tr '\n' ' ')
docker save -o bisheng_offline.tar $IMG_LINE

if [ $? -eq 0 ]; then
    echo "✅ 打包成功！文件名为: bisheng_offline.tar"
    ls -lh bisheng_offline.tar
else
    echo "❌ 打包失败。"
fi
