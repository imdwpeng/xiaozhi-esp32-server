@echo off

REM 项目根目录
set PROJECT_ROOT=%~dp0

REM Docker镜像名称和标签
set IMAGE_NAME=xiaozhi-esp32-server
set IMAGE_TAG=latest
set WEB_IMAGE_NAME=xiaozhi-esp32-server-web
set WEB_IMAGE_TAG=latest

REM 阿里云服务器信息
set ALIYUN_SERVER=47.113.222.41
set ALIYUN_REGISTRY=%ALIYUN_SERVER%:5000
set ALIYUN_IMAGE=%ALIYUN_REGISTRY%/%IMAGE_NAME%:%IMAGE_TAG%
set ALIYUN_WEB_IMAGE=%ALIYUN_REGISTRY%/%WEB_IMAGE_NAME%:%WEB_IMAGE_TAG%
set ALIYUN_USER=root

REM SSH配置说明：
REM 1. 建议配置SSH密钥对实现免密码登录
REM 2. 如果未配置密钥，执行脚本时会提示输入密码
REM 3. 配置方法：
REM    a. 在本地生成密钥：ssh-keygen -t rsa
REM    b. 将公钥复制到服务器：ssh-copy-id %ALIYUN_USER%@%ALIYUN_SERVER%
REM    c. 测试免密码登录：ssh %ALIYUN_USER%@%ALIYUN_SERVER%

echo ========================================
echo 开始构建和推送Docker镜像
echo ========================================

REM 1. 进入项目根目录
cd /d %PROJECT_ROOT%

REM 2. 构建基础镜像（如果需要）
echo 正在构建基础镜像...
docker build -t %IMAGE_NAME%-base -f Dockerfile-server-base .
if %errorlevel% neq 0 (
    echo 基础镜像构建失败！
    pause
    exit /b 1
)

echo 基础镜像构建成功！

REM 3. 构建生产镜像
echo 正在构建Server生产镜像...
docker build -t %IMAGE_NAME%:%IMAGE_TAG% -f Dockerfile-server .
if %errorlevel% neq 0 (
    echo Server生产镜像构建失败！
    pause
    exit /b 1
)

echo Server生产镜像构建成功！

REM 4. 构建Web镜像
echo 正在构建Web镜像...
docker build -t %WEB_IMAGE_NAME%:%WEB_IMAGE_TAG% -f Dockerfile-web .
if %errorlevel% neq 0 (
    echo Web镜像构建失败！
    pause
    exit /b 1
)

echo Web镜像构建成功！

REM 5. 为镜像添加阿里云标签
echo 正在为Server镜像添加阿里云标签...
docker tag %IMAGE_NAME%:%IMAGE_TAG% %ALIYUN_IMAGE%
if %errorlevel% neq 0 (
    echo Server镜像标签添加失败！
    pause
    exit /b 1
)

echo 正在为Web镜像添加阿里云标签...
docker tag %WEB_IMAGE_NAME%:%WEB_IMAGE_TAG% %ALIYUN_WEB_IMAGE%
if %errorlevel% neq 0 (
    echo Web镜像标签添加失败！
    pause
    exit /b 1
)

echo 镜像标签添加成功！

REM 6. 通过SSH推送镜像到阿里云服务器
echo 正在通过SSH推送镜像到阿里云服务器 %ALIYUN_SERVER%...

REM 6.1 保存镜像为tar文件
echo 正在保存Server镜像为tar文件...
docker save -o %IMAGE_NAME%_%IMAGE_TAG%.tar %IMAGE_NAME%:%IMAGE_TAG%
if %errorlevel% neq 0 (
    echo Server镜像保存失败！
    pause
    exit /b 1
)

echo Server镜像保存成功！

echo 正在保存Web镜像为tar文件...
docker save -o %WEB_IMAGE_NAME%_%WEB_IMAGE_TAG%.tar %WEB_IMAGE_NAME%:%WEB_IMAGE_TAG%
if %errorlevel% neq 0 (
    echo Web镜像保存失败！
    del %IMAGE_NAME%_%IMAGE_TAG%.tar
    pause
    exit /b 1
)

echo Web镜像保存成功！

REM 5.2 通过SSH将tar文件传输到阿里云服务器
echo 正在通过SSH传输tar文件到阿里云服务器...
scp %IMAGE_NAME%_%IMAGE_TAG%.tar %ALIYUN_USER%@%ALIYUN_SERVER%:/tmp/
if %errorlevel% neq 0 (
    echo 文件传输失败！
    del %IMAGE_NAME%_%IMAGE_TAG%.tar
    pause
    exit /b 1
)

echo 文件传输成功！

REM 5.3 通过SSH在阿里云服务器上加载镜像并升级
echo 正在通过SSH在阿里云服务器上加载镜像并升级...

REM 先将本地的docker-compose_all.yml文件复制到服务器
echo 正在复制本地docker-compose_all.yml文件到服务器...
scp main/xiaozhi-server/docker-compose_all.yml %ALIYUN_USER%@%ALIYUN_SERVER%:/tmp/docker-compose_all.yml
if %errorlevel% neq 0 (
    echo docker-compose_all.yml文件复制失败！
    del %IMAGE_NAME%_%IMAGE_TAG%.tar
    del %WEB_IMAGE_NAME%_%WEB_IMAGE_TAG%.tar
    pause
    exit /b 1
)

echo docker-compose_all.yml文件复制成功！

REM 6.2 通过SSH将tar文件传输到阿里云服务器
echo 正在通过SSH传输Server镜像tar文件到阿里云服务器...
scp %IMAGE_NAME%_%IMAGE_TAG%.tar %ALIYUN_USER%@%ALIYUN_SERVER%:/tmp/
if %errorlevel% neq 0 (
    echo Server镜像文件传输失败！
    del %IMAGE_NAME%_%IMAGE_TAG%.tar
    del %WEB_IMAGE_NAME%_%WEB_IMAGE_TAG%.tar
    pause
    exit /b 1
)

echo Server镜像文件传输成功！

echo 正在通过SSH传输Web镜像tar文件到阿里云服务器...
scp %WEB_IMAGE_NAME%_%WEB_IMAGE_TAG%.tar %ALIYUN_USER%@%ALIYUN_SERVER%:/tmp/
if %errorlevel% neq 0 (
    echo Web镜像文件传输失败！
    del %IMAGE_NAME%_%IMAGE_TAG%.tar
    del %WEB_IMAGE_NAME%_%WEB_IMAGE_TAG%.tar
    pause
    exit /b 1
)

echo Web镜像文件传输成功！

REM 6.3 执行升级操作
ssh %ALIYUN_USER%@%ALIYUN_SERVER% "\
# 加载Server镜像\
echo '正在加载Server镜像...'\
docker load -i /tmp/%IMAGE_NAME%_%IMAGE_TAG%.tar && \
docker tag %IMAGE_NAME%:%IMAGE_TAG% %ALIYUN_IMAGE% && \
\
# 加载Web镜像\
echo '正在加载Web镜像...'\
docker load -i /tmp/%WEB_IMAGE_NAME%_%WEB_IMAGE_TAG%.tar && \
docker tag %WEB_IMAGE_NAME%:%WEB_IMAGE_TAG% %ALIYUN_WEB_IMAGE% && \
\
# 清理临时文件\
rm /tmp/%IMAGE_NAME%_%IMAGE_TAG%.tar /tmp/%WEB_IMAGE_NAME%_%WEB_IMAGE_TAG%.tar && \
\
# 开始升级操作\
echo '开始升级小智服务端...'\
\
# 1. 停止并移除现有容器\
echo '正在停止并移除现有容器...'\
# 停止并删除特定容器（考虑容器可能不存在的情况）\
containers=(\
    "xiaozhi-esp32-server"\
    "xiaozhi-esp32-server-web"\
    # 保留数据库和redis容器，避免数据丢失\
    # "xiaozhi-esp32-server-db"\
    # "xiaozhi-esp32-server-redis"\
)\
\
for container in "${containers[@]}"; do\
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then\
        docker stop "$container" >/dev/null 2>&1 && \
        docker rm "$container" >/dev/null 2>&1 && \
        echo "成功移除容器: $container"\
    else\
        echo "容器不存在，跳过: $container"\
    fi\
done\
\
# 2. 复制并修改docker-compose_all.yml文件\
echo '正在配置docker-compose_all.yml文件...'\
mkdir -p /opt/xiaozhi-server/\
cp /tmp/docker-compose_all.yml /opt/xiaozhi-server/docker-compose_all.yml\
\
# 修改docker-compose文件，使用我们推送的本地镜像\
sed -i 's|ghcr.nju.edu.cn/xinnan-tech/xiaozhi-esp32-server:server_latest|%ALIYUN_IMAGE%|g' /opt/xiaozhi-server/docker-compose_all.yml && \
sed -i 's|ghcr.nju.edu.cn/xinnan-tech/xiaozhi-esp32-server:web_latest|%ALIYUN_WEB_IMAGE%|g' /opt/xiaozhi-server/docker-compose_all.yml && \
echo 'docker-compose_all.yml文件配置完成！'\
\
# 3. 启动最新版本服务\
echo '正在启动最新版本服务...'\
docker compose -f /opt/xiaozhi-server/docker-compose_all.yml up -d\
\
echo '升级完成！'"
if %errorlevel% neq 0 (
    echo 镜像加载或升级失败！
    del %IMAGE_NAME%_%IMAGE_TAG%.tar
    del %WEB_IMAGE_NAME%_%WEB_IMAGE_TAG%.tar
    pause
    exit /b 1
)

echo 镜像加载和升级成功！

REM 5.4 删除本地tar文件
echo 正在删除本地tar文件...
del %IMAGE_NAME%_%IMAGE_TAG%.tar %WEB_IMAGE_NAME%_%WEB_IMAGE_TAG%.tar
if %errorlevel% neq 0 (
    echo 本地tar文件删除失败！
    pause
    exit /b 1
)

echo 本地tar文件删除成功！

REM 6. 清理本地临时标签（可选）
echo 正在清理本地临时标签...
docker rmi %ALIYUN_IMAGE% %ALIYUN_WEB_IMAGE% 2>nul || echo 本地标签不存在，跳过清理

echo 本地标签清理完成！

echo ========================================
echo Docker镜像构建和推送完成！
echo 镜像已成功推送到：%ALIYUN_IMAGE%
echo ========================================
pause