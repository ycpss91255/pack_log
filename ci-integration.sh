#!/bin/bash

# 自動偵測 Docker Compose 指令
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif docker-compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "Error: Docker Compose is not installed."
    exit 1
fi

# 傳遞宿主機的 UID 和 GID 供 Docker 內部修正權限使用
export HOST_UID=$(id -u)
export HOST_GID=$(id -g)

# 執行遠端整合測試
$DOCKER_COMPOSE -f docker-compose.integration.yaml run --rm integration
EXIT_CODE=$?

# 清理容器
$DOCKER_COMPOSE -f docker-compose.integration.yaml down

exit $EXIT_CODE
