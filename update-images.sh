#!/bin/sh
# 脚本作者@VanillaNahida
# 本脚本用于在云服务器上更新小智ESP32服务端镜像
# 支持X86版本的Ubuntu系统

# 定义中断处理函数
handle_interrupt() {
    echo ""
    echo "更新已被用户中断(Ctrl+C)"
    echo "请再次运行脚本以重启更新"
    exit 1
}

# 设置信号捕获，处理Ctrl+C
trap handle_interrupt SIGINT

# 检查root权限
if [ $EUID -ne 0 ]; then
    echo "请使用root权限运行本脚本"
    exit 1
fi

# 检查系统版本
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
        echo "该脚本只支持Debian/Ubuntu系统"
        exit 1
    fi
else
    echo "无法确定系统版本，该脚本只支持Debian/Ubuntu系统"
    exit 1
fi

# 检查Docker是否安装
if ! command -v docker &> /dev/null; then
    echo "未检测到Docker，请先安装Docker"
    exit 1
fi

# 检查镜像文件是否存在并验证完整性
echo "------------------------------------------------------------"
echo "检查镜像文件是否存在..."

SERVER_IMAGE_FILE="/tmp/xiaozhi-esp32-server-server.tar"
WEB_IMAGE_FILE="/tmp/xiaozhi-esp32-server-web.tar"

if [ ! -f "$SERVER_IMAGE_FILE" ] || [ ! -f "$WEB_IMAGE_FILE" ]; then
    echo "错误：镜像文件不存在！"
    echo "请确保以下文件已上传到/tmp目录："
    echo "- $SERVER_IMAGE_FILE"
    echo "- $WEB_IMAGE_FILE"
    exit 1
fi

# 检查文件大小，确保文件不为空
echo "检查镜像文件完整性..."
SERVER_SIZE=$(du -b "$SERVER_IMAGE_FILE" | cut -f1)
WEB_SIZE=$(du -b "$WEB_IMAGE_FILE" | cut -f1)

if [ "$SERVER_SIZE" -lt 1048576 ]; then  # 小于1MB
    echo "错误：Server镜像文件太小，可能已损坏！"
    exit 1
fi

if [ "$WEB_SIZE" -lt 1048576 ]; then  # 小于1MB
    echo "错误：Web镜像文件太小，可能已损坏！"
    exit 1
fi

echo "镜像文件检查通过！"

# 处理语音识别模型文件
echo "------------------------------------------------------------"
echo "处理语音识别模型文件..."

# 定义模型相关路径
MODEL_DIR="/opt/xiaozhi-server/models/SenseVoiceSmall"
MODEL_PATH="$MODEL_DIR/model.pt"

# 确保模型目录存在
if [ ! -d "$MODEL_DIR" ]; then
    echo "创建模型目录: $MODEL_DIR"
    mkdir -p "$MODEL_DIR"
fi

# 检查模型文件是否是目录，如果是则删除
if [ -d "$MODEL_PATH" ]; then
    echo "发现模型文件路径是目录，正在删除..."
    rm -rf "$MODEL_PATH"
fi

# 检查/tmp目录中是否有模型文件，如果有则复制
if [ -f "/tmp/model.pt" ]; then
    echo "从/tmp目录复制模型文件到目标位置..."
    cp /tmp/model.pt "$MODEL_PATH"
    echo "模型文件复制完成！"
else
    # 下载模型文件
    if [ ! -f "$MODEL_PATH" ]; then
        echo "从网络下载模型文件..."
        curl -fL --progress-bar https://modelscope.cn/models/iic/SenseVoiceSmall/resolve/master/model.pt -o "$MODEL_PATH" || {
            echo "model.pt文件下载失败，使用空文件占位符"
            touch "$MODEL_PATH"
        }
    else
        echo "model.pt文件已存在，跳过处理"
    fi
fi

# 最终验证模型文件类型
echo "验证模型文件类型..."
if [ -f "$MODEL_PATH" ]; then
    echo "✓ 模型文件类型正确: $MODEL_PATH"
    echo "  文件大小: $(du -h "$MODEL_PATH" | cut -f1)"
else
    echo "✗ 模型文件类型错误: $MODEL_PATH"
    echo "  当前类型: $(if [ -d "$MODEL_PATH" ]; then echo "目录"; elif [ -e "$MODEL_PATH" ]; then echo "其他"; else echo "不存在"; fi)"
    echo "  正在创建空文件占位符..."
    touch "$MODEL_PATH"
    echo "✓ 已创建空文件占位符"
fi

# 停止server和web服务，但保留db和redis容器
echo "------------------------------------------------------------"
echo "停止现有服务..."

# 只停止server和web容器，不使用docker compose down以保留db和redis
for container in "xiaozhi-esp32-server" "xiaozhi-esp32-server-web"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        docker stop "$container" >/dev/null 2>&1 && \
        echo "成功停止容器: $container"
    fi
done

# 停止并删除特定容器（考虑容器可能不存在的情况）
# 注意：不删除db和redis容器，因为它们包含持久化数据
containers=(
    "xiaozhi-esp32-server"
    "xiaozhi-esp32-server-web"
)

for container in "${containers[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        docker stop "$container" >/dev/null 2>&1 && \
        docker rm "$container" >/dev/null 2>&1 && \
        echo "成功移除容器: $container"
    else
        echo "容器不存在，跳过: $container"
    fi
done

# 删除特定镜像（考虑镜像可能不存在的情况）
images=(
    "xiaozhi-esp32-server:server_latest"
    "xiaozhi-esp32-server:web_latest"
    "ghcr.nju.edu.cn/xinnan-tech/xiaozhi-esp32-server:server_latest"
    "ghcr.nju.edu.cn/xinnan-tech/xiaozhi-esp32-server:web_latest"
)

for image in "${images[@]}"; do
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image}$"; then
        docker rmi "$image" >/dev/null 2>&1 && \
        echo "成功删除镜像: $image"
    else
        echo "镜像不存在，跳过: $image"
    fi
done

echo "所有清理操作完成"

# 加载新镜像（支持重试机制）
echo "------------------------------------------------------------"
echo "加载新镜像..."

# 定义重试函数
retry_docker_load() {
    local image_file=$1
    local image_name=$2
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo "加载$image_name镜像（尝试 $((retry_count + 1))/$max_retries）..."
        
        # 获取文件大小用于进度估算
        local file_size=$(du -b "$image_file" | cut -f1)
        local file_size_mb=$(echo "scale=2; $file_size / 1048576" | bc)
        echo "镜像大小: ${file_size_mb} MB"
        
        # 显示加载镜像的详细进度
        echo "正在加载镜像，显示详细进度..."
        echo "镜像层加载过程中会显示每个层的ID和状态，这是正常现象..."
        
        # 使用docker load直接加载镜像，显示详细输出
        if docker load -i "$image_file"; then
            echo "成功加载$image_name镜像！"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        echo "加载$image_name镜像失败，5秒后重试..."
        sleep 5
    done
    
    echo "加载$image_name镜像失败，已重试$max_retries次！"
    return 1
}

# 加载镜像（支持重试）
retry_docker_load "$SERVER_IMAGE_FILE" "Server" || {
    echo "加载Server镜像失败！"
    exit 1
}

retry_docker_load "$WEB_IMAGE_FILE" "Web" || {
    echo "加载Web镜像失败！"
    exit 1
}

# 验证加载的镜像
 echo "------------------------------------------------------------"
 echo "验证加载的镜像..."
 docker images | grep xiaozhi-esp32-server

echo "镜像加载完成！"

# 启动Docker服务
echo "------------------------------------------------------------"
echo "启动最新版本服务..."

# 检测docker compose命令形式（支持docker-compose和docker compose两种形式）
if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "错误：未找到docker-compose或docker compose命令！"
    exit 1
fi

# 使用检测到的命令启动服务
 echo "正在启动所有服务..."
 echo "使用配置文件: /opt/xiaozhi-server/docker-compose_all.yml"
 echo "执行命令: $DOCKER_COMPOSE_CMD -f /opt/xiaozhi-server/docker-compose_all.yml up -d"

# 检查配置文件是否存在
if [ ! -f /opt/xiaozhi-server/docker-compose_all.yml ]; then
    echo "错误：配置文件 /opt/xiaozhi-server/docker-compose_all.yml 不存在！"
    exit 1
fi

# 显示配置文件中的镜像配置，用于调试
echo "配置文件中的镜像配置："
grep -A 5 "image:" /opt/xiaozhi-server/docker-compose_all.yml

# 启动服务
$DOCKER_COMPOSE_CMD -f /opt/xiaozhi-server/docker-compose_all.yml up -d

if [ $? -ne 0 ]; then
    echo "Docker服务启动失败，请检查日志"
    echo "显示docker-compose日志："
    $DOCKER_COMPOSE_CMD -f /opt/xiaozhi-server/docker-compose_all.yml logs --tail 50
    exit 1
fi

# 显示所有容器状态，用于调试
echo "------------------------------------------------------------"
echo "启动后所有容器状态："
docker ps -a

# 检查服务启动状态
echo "------------------------------------------------------------"
echo "检查服务启动状态..."
TIMEOUT=300
START_TIME=$(date +%s)

# 检查web容器和server容器的启动状态
while true; do
    CURRENT_TIME=$(date +%s)
    if [ $((CURRENT_TIME - START_TIME)) -gt $TIMEOUT ]; then
        echo "服务启动超时，未在指定时间内找到预期日志内容"
        exit 1
    fi
    
    # 检查web容器启动状态
    WEB_READY=$(docker logs xiaozhi-esp32-server-web 2>&1 | grep -q "Started AdminApplication in" && echo 1 || echo 0)
    
    # 检查server容器运行状态（python app.py启动后会持续运行）
    SERVER_RUNNING=$(docker ps --format '{{.Names}}' | grep -q "^xiaozhi-esp32-server$" && echo 1 || echo 0)
    
    if [ $WEB_READY -eq 1 ] && [ $SERVER_RUNNING -eq 1 ]; then
        echo "所有服务启动成功！"
        break
    fi
    
    echo "等待服务启动... Web: $WEB_READY, Server: $SERVER_RUNNING"
    sleep 5
done

# 重启服务确保所有组件正常运行
echo "正在完成最终配置..."
echo "正在重启服务以确保所有组件正常运行..."
$DOCKER_COMPOSE_CMD -f /opt/xiaozhi-server/docker-compose_all.yml up -d
echo "服务启动完成！"

# 获取并显示地址信息
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo "------------------------------------------------------------"
echo -e "\e[1;32m服务更新完成！\e[0m"
echo "服务端相关地址如下："
echo "管理后台访问地址: http://$LOCAL_IP:8002"
echo "OTA 地址: http://$LOCAL_IP:8002/xiaozhi/ota/"
echo "视觉分析接口地址: http://$LOCAL_IP:8003/mcp/vision/explain"
echo "WebSocket 地址: ws://$LOCAL_IP:8000/xiaozhi/v1/"
echo ""
echo "感谢您的使用！"