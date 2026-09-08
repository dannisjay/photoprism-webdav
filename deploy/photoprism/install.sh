#!/usr/bin/env bash
# 在 Ubuntu 服务器上：sudo bash install.sh
# 结果：/opt/photoprism 下 compose+ .env，容器起在 2342 端口
set -euo pipefail

DEST=/opt/photoprism
SRC="$(cd "$(dirname "$0")" && pwd)"

sudo mkdir -p "${DEST}"
sudo cp "${SRC}/compose.yaml" "${DEST}/"
if [ ! -f "${DEST}/.env" ]; then
  sudo cp "${SRC}/.env.example" "${DEST}/.env"
  echo "已生成 ${DEST}/.env —— 请先 sudo nano ${DEST}/.env 修改配置"
  echo "  - 想马上看界面：保持 WEBDAV_SKIP_MOUNT=true"
  echo "  - 想扫 115：改 WEBDAV_SKIP_MOUNT=false 并填 WEBDAV_URL/USER/PASS/MOUNTS"
  echo "  - PHOTOPRISM_ADMIN_PASSWORD 至少 8 位"
  exit 0
fi

cd "${DEST}"
sudo docker compose pull
sudo docker compose up -d
echo
echo "完成。浏览器打开 http://<服务器IP>:2342/   （用户名 admin）"
echo "日志：sudo docker compose -f ${DEST}/compose.yaml logs -f"