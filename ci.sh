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

# 執行 CI 流程
$DOCKER_COMPOSE run --rm ci
