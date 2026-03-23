#!/bin/bash

# ================= 配置区域 =================
SOURCE_DIR="docker"
# 生成时间戳
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 定义最终想要的文件名
FINAL_DIR_NAME="docker_bak_${TIMESTAMP}"
FINAL_TAR_NAME="${FINAL_DIR_NAME}.tar.gz"

# 定义带有“处理中”前缀的临时文件名
PREFIX="ing_"
TEMP_DIR_NAME="${PREFIX}${FINAL_DIR_NAME}"  # 例如: ing_docker_bak_2023...
TEMP_TAR_NAME="${PREFIX}${FINAL_TAR_NAME}"  # 例如: ing_docker_bak_2023...tar.gz

# ===========================================

# 0. 检查源目录
if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ 错误: 目录 '$SOURCE_DIR' 不存在"
    exit 1
fi

echo "🚀 [1/3] 开始复制目录 (临时名称: $TEMP_DIR_NAME)..."

# 1. 复制目录 (复制到带前缀的目录)
if command -v rsync >/dev/null 2>&1; then
    rsync -ah --info=progress2 --no-i-r "$SOURCE_DIR/" "$TEMP_DIR_NAME/"
else
    cp -rp "$SOURCE_DIR" "$TEMP_DIR_NAME"
fi

# 检查复制是否成功
if [ $? -ne 0 ]; then
    echo "❌ 复制失败，停止脚本"
    exit 1
fi
echo -e "\n✅ 复制完成"

echo "📦 [2/3] 开始压缩 (临时文件: $TEMP_TAR_NAME)..."

# 2. 打包压缩 (打包为带前缀的压缩包)
# 注意：这里我们打包的是那个带前缀的目录
tar -czf "$TEMP_TAR_NAME" \
    --checkpoint=100 \
    --checkpoint-action=ttyout='   正在处理第 %u 个文件...\r' \
    "$TEMP_DIR_NAME"

# 检查压缩是否成功
if [ $? -ne 0 ]; then
    echo -e "\n❌ 压缩失败，保留临时文件以便检查"
    exit 1
fi
echo -e "\n✅ 压缩完成"

# 3. 收尾工作：重命名 & 清理
echo "✨ [3/3] 验证成功，执行重命名和清理..."

# A. 去除压缩包的前缀 (变成正式文件)
mv "$TEMP_TAR_NAME" "$FINAL_TAR_NAME"
echo "   -> 最终产物已生成: $FINAL_TAR_NAME"

# B. 删除临时复制的目录
rm -rf "$TEMP_DIR_NAME"
echo "   -> 临时目录已删除: $TEMP_DIR_NAME"

echo "🎉 所有任务圆满结束！"
