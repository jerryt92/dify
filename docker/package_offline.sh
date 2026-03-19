#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check docker-compose file
if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.yaml" ]; then
    echo -e "${RED}❌ 错误：当前目录下未找到 docker-compose.yml${NC}"
    exit 1
fi

# ===========================
# 1. 选择架构
# ===========================
echo -e "${CYAN}🏗️  请选择目标镜像架构:${NC}"
echo "1) linux/amd64 (常见的 x86 服务器)"
echo "2) linux/arm64 (Apple Silicon, 树莓派等)"
read -p "请输入选项 [1-2, 默认 1]: " ARCH_CHOICE

case $ARCH_CHOICE in
    2)
        PLATFORM="linux/arm64"
        ARCH_NAME="arm64"
        ;;
    *)
        PLATFORM="linux/amd64"
        ARCH_NAME="amd64"
        ;;
esac

echo -e "✅ 已选择架构: ${GREEN}${PLATFORM}${NC}"
echo "----------------------------------------"

# ===========================
# 2. 读取并列出镜像 (自动去重)
# ===========================
echo "🔍 正在读取镜像列表 (自动去重)..."

# 使用 sort -u 进行去重，防止同一个镜像出现多次导致序号混乱
ALL_IMAGES=($(docker compose config --images | sort -u | grep -v "^$"))

if [ ${#ALL_IMAGES[@]} -eq 0 ]; then
    echo -e "${RED}❌ 错误：未能读取到任何镜像列表。${NC}"
    exit 1
fi

echo -e "${CYAN}📋 发现以下唯一镜像：${NC}"
i=1
for img in "${ALL_IMAGES[@]}"; do
    echo -e "${YELLOW}$i.${NC} $img"
    ((i++))
done

# ===========================
# 3. 选择要打包的镜像
# ===========================
echo ""
echo -e "${CYAN}👉 请输入要打包的镜像序号${NC}"
echo "   - 用逗号分隔 (例如: 1,3,5)"
echo "   - 支持中文逗号"
echo "   - 直接回车 = 打包所有"
read -p "请输入: " SELECTION

TARGET_IMAGES=""

if [ -z "$SELECTION" ]; then
    echo "👉 未输入序号，默认选中 **所有** 镜像。"
    TARGET_IMAGES="${ALL_IMAGES[@]}"
else
    # 替换中文逗号为英文逗号，再将逗号换为空格
    SELECTION=${SELECTION//，/,}
    SELECTION_SPACES=${SELECTION//,/ }

    echo "👉 正在解析选择..."

    for index in $SELECTION_SPACES; do
        # 检查是否为数字
        if ! [[ "$index" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}⚠️  跳过非数字输入: $index${NC}"
            continue
        fi

        actual_index=$((index-1))

        # 检查序号是否有效
        if [ -n "${ALL_IMAGES[$actual_index]}" ]; then
            TARGET_IMAGES="$TARGET_IMAGES ${ALL_IMAGES[$actual_index]}"
        else
            echo -e "${RED}⚠️  警告：序号 $index 超出范围，已跳过${NC}"
        fi
    done
fi

if [ -z "$TARGET_IMAGES" ]; then
     echo -e "${RED}❌ 错误：未选中任何有效镜像，退出。${NC}"
     exit 1
fi

# ===========================
# 4. 最终确认与拉取选项
# ===========================
echo "----------------------------------------"
echo -e "${CYAN}📦 准备打包清单:${NC}"
for img in $TARGET_IMAGES; do
    echo -e "   - ${GREEN}$img${NC}"
done
echo "----------------------------------------"

read -p "是否跳过全局拉取过程，优先使用本地已有镜像？ (y/n) [默认 y]: " SKIP_PULL
SKIP_PULL=${SKIP_PULL:-y}

if [[ "$SKIP_PULL" == "y" || "$SKIP_PULL" == "Y" ]]; then
    echo -e "✅ 已选择 ${GREEN}跳过全局拉取${NC}，将优先使用本地镜像。"
    DO_PULL=false
else
    echo -e "✅ 已选择 ${GREEN}拉取最新镜像${NC} (架构: $PLATFORM)。"
    DO_PULL=true
fi
echo "----------------------------------------"

# ===========================
# 5. 执行验证与拉取
# ===========================
echo ""
FINAL_TARGET_IMAGES="" # 用于存放最终确实存在的镜像，防止 save 报错

for img in $TARGET_IMAGES; do
    if [ "$DO_PULL" = true ]; then
        echo -e "⏳ [正在拉取] $img ..."
        docker pull --platform "$PLATFORM" "$img"
        if [ $? -eq 0 ]; then
            FINAL_TARGET_IMAGES="$FINAL_TARGET_IMAGES $img"
        else
            echo -e "${RED}❌ 拉取失败: $img，将跳过打包该镜像。${NC}"
        fi
    else
        # 检查本地是否存在该镜像
        if docker image inspect "$img" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ 本地已存在: $img${NC}"
            FINAL_TARGET_IMAGES="$FINAL_TARGET_IMAGES $img"
        else
            echo -e "${YELLOW}⚠️ 本地未找到镜像: $img${NC}"
            read -p "   👉 是否现在拉取该镜像？ (y/n) [默认 y]: " PULL_MISSING
            PULL_MISSING=${PULL_MISSING:-y}

            if [[ "$PULL_MISSING" == "y" || "$PULL_MISSING" == "Y" ]]; then
                echo -e "⏳ [正在拉取] $img ..."
                docker pull --platform "$PLATFORM" "$img"
                if [ $? -eq 0 ]; then
                    FINAL_TARGET_IMAGES="$FINAL_TARGET_IMAGES $img"
                else
                    echo -e "${RED}❌ 拉取失败: $img，将跳过打包该镜像。${NC}"
                fi
            else
                echo -e "⏩ 已跳过: $img"
            fi
        fi
    fi
done

# ===========================
# 6. 打包镜像
# ===========================
echo "----------------------------------------"
if [ -z "$FINAL_TARGET_IMAGES" ]; then
    echo -e "${RED}❌ 错误：经过筛选后，没有可用于打包的有效镜像，操作取消。${NC}"
    exit 1
fi

OUTPUT_FILENAME="images_offline_${ARCH_NAME}.tar"
echo -e "📦 [正在打包] 最终将打包以下镜像保存为 ${OUTPUT_FILENAME} ..."
for img in $FINAL_TARGET_IMAGES; do
    echo -e "   - ${GREEN}$img${NC}"
done

docker save -o "$OUTPUT_FILENAME" $FINAL_TARGET_IMAGES

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✅ 打包成功！${NC}"
    ls -lh "$OUTPUT_FILENAME"
    echo -e "${GREEN}现在可以将 ${OUTPUT_FILENAME} 传输到离线服务器了。${NC}"
else
    echo -e "\n${RED}❌ 打包失败，请检查 Docker 服务或磁盘空间。${NC}"
fi