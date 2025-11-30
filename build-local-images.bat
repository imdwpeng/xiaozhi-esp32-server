@echo off
chcp 65001 >nul

:: 定义镜像文件名称
set SERVER_IMAGE=xiaozhi-esp32-server-server.tar
set WEB_IMAGE=xiaozhi-esp32-server-web.tar
set DEPLOY_DIR=deploy

:: 检查deploy目录是否存在，以及是否包含两个镜像文件
if exist %DEPLOY_DIR%\%SERVER_IMAGE% if exist %DEPLOY_DIR%\%WEB_IMAGE% (
    echo 检测到deploy目录中已存在两个镜像文件，直接上传...
    echo.
    goto UPLOAD_IMAGE
)

:: 构建镜像流程
echo 开始构建本地Docker镜像...
echo.
echo 1. 构建基础镜像...
docker build -t xiaozhi-esp32-server:server-base -f ./Dockerfile-server-base .
if %errorlevel% neq 0 (
    echo 构建基础镜像失败!
    exit /b %errorlevel%
)
echo 基础镜像构建完成!
echo.
echo 2. 构建Server镜像...
docker build -t xiaozhi-esp32-server:server_latest -f ./Dockerfile-server .
if %errorlevel% neq 0 (
    echo 构建Server镜像失败!
    exit /b %errorlevel%
)
echo Server镜像构建完成!
echo.
echo 3. 构建Web镜像...
docker build -t xiaozhi-esp32-server:web_latest -f ./Dockerfile-web .
if %errorlevel% neq 0 (
    echo 构建Web镜像失败!
    exit /b %errorlevel%
)
echo Web镜像构建完成!
echo.
echo 所有镜像构建完成!
echo.
echo 保存Docker镜像到本地文件...
if not exist %DEPLOY_DIR% mkdir %DEPLOY_DIR%
docker save -o %DEPLOY_DIR%/%SERVER_IMAGE% xiaozhi-esp32-server:server_latest
if %errorlevel% neq 0 (
    echo 保存Server镜像失败!
    exit /b %errorlevel%
)
docker save -o %DEPLOY_DIR%/%WEB_IMAGE% xiaozhi-esp32-server:web_latest
if %errorlevel% neq 0 (
    echo 保存Web镜像失败!
    exit /b %errorlevel%
)
echo Docker镜像保存完成!
echo.

:UPLOAD_IMAGE
echo 推送镜像到服务器 47.113.222.41...
set ALIYUN_SERVER=47.113.222.41
scp -r -C %DEPLOY_DIR%\%SERVER_IMAGE% %DEPLOY_DIR%\%WEB_IMAGE% root@%ALIYUN_SERVER%:/tmp/
if %errorlevel% neq 0 (
    echo 推送镜像到服务器失败!
    exit /b %errorlevel%
)
echo 镜像推送完成!
echo.

:: 删除deploy目录中的镜像文件
echo 删除deploy目录中的镜像文件...
del %DEPLOY_DIR%\%SERVER_IMAGE% %DEPLOY_DIR%\%WEB_IMAGE% >nul 2>&1
echo 镜像文件已删除!
echo.
echo 镜像已推送到服务器 47.113.222.41，请手动在服务器上执行后续部署操作。
