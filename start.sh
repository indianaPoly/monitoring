#!/bin/bash

# Get script base path
BASE_PATH=$(cd "$(dirname "$0")"; pwd)

# step 1 : docker network
if ! docker network ls | grep -q monitor_net; then
    echo "[INFO] Creating docker network >>> monitor_net"
    docker network create monitor_net
fi

# step 2 : db start
echo "[INFO] Starting DB >>> mysql"
docker-compose -f "$BASE_PATH/DB/mysql/docker-compose.yml" --env-file "$BASE_PATH/DB/mysql/.env" up -d

# step 3 : monitoring start
echo "[INFO] Starting Monitoring >>> Prometheus and Grafana"
docker-compose -f "$BASE_PATH/monitoring/docker-compose.yml" --env-file "$BASE_PATH/monitoring/.env" up -d

echo "[SUCCESS] All Services started!"
