#!/usr/bin/env bash
# PhotoPrism Local v1.0 部署/升级脚本
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  cp .env.example .env
  echo "已生成 .env。请先编辑 .env 中的 WEBDAV_URL/USER/PASS/PATH 和管理员密码，再运行本脚本。"
  exit 1
fi

docker compose up -d --build
echo
echo "启动完成。查看日志：docker compose logs -f photoprism"
echo "首次入库（也可等容器启动约 5 分钟后自动索引）："
echo "  docker compose exec photoprism photoprism index"