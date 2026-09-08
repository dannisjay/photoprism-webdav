#!/usr/bin/env bash
# 增量索引：把网盘里新增的照片扫进库
# 用法：scripts/index.sh            # 全量增量扫描
#       scripts/index.sh --cleanup  # 顺便清理已删除文件记录
set -euo pipefail
cd "$(dirname "$0")/.."
exec docker compose exec -T photoprism photoprism index "$@"