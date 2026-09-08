#!/usr/bin/env bash
# PhotoPrism Local v1.0
# 启动时把 Alist(115) 的 WebDAV 目录（可多个）只读挂载为
# /photoprism/originals/<挂载名>，全部就绪后移交 photoprism 启动。
# 配置来自环境变量（.env）：
#   WEBDAV_URL        WebDAV 根，形如 http://<ip>:5244/dav
#   WEBDAV_USER/PASS  Alist 登录账号/密码
#   WEBDAV_MOUNTS     多目录： 远程路径:挂载名;远程路径:挂载名
#   RCLONE_VFS_CACHE  是否开启原图磁盘缓存（默认 true，断线也能重看大图）
#   其余 RCLONE_*     超时/重试/缓存上限等调优参数，见 .env.example
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/photoprism/bin"

: "${WEBDAV_URL:?请在 .env 设置 WEBDAV_URL（Alist WebDAV 地址，形如 http://服务器IP:5244/dav）}"
: "${WEBDAV_USER:?请在 .env 设置 WEBDAV_USER（Alist 登录账号）}"
: "${WEBDAV_PASS:?请在 .env 设置 WEBDAV_PASS（Alist 登录密码）}"

MOUNT_ROOT="/photoprism/originals"
LOG_FILE="/photoprism/storage/rclone.log"
VFS_CACHE_DIR="/photoprism/storage/rclone-vfs"

# 兼容旧变量 WEBDAV_PATH
if [[ -z "${WEBDAV_MOUNTS:-}" ]]; then
  WEBDAV_MOUNTS="${WEBDAV_PATH:-}"
fi
if [[ -z "${WEBDAV_MOUNTS}" ]]; then
  echo "[webdav] 未设置 WEBDAV_MOUNTS（或 WEBDAV_PATH），请在 .env 中填写要扫描的目录"
  exit 1
fi

# ---- 容错/缓存调优参数（可在 .env 覆盖）----
RCLONE_VFS_CACHE="${RCLONE_VFS_CACHE:-true}"
RCLONE_CONTIMEOUT="${RCLONE_CONTIMEOUT:-10s}"
RCLONE_TIMEOUT="${RCLONE_TIMEOUT:-5m}"
RCLONE_RETRIES="${RCLONE_RETRIES:-3}"
RCLONE_LOW_LEVEL_RETRIES="${RCLONE_LOW_LEVEL_RETRIES:-20}"
RCLONE_VFS_CACHE_MAX_SIZE="${RCLONE_VFS_CACHE_MAX_SIZE:-50G}"

VFS_MODE="off"
if [[ "${RCLONE_VFS_CACHE}" == "true" ]]; then
  VFS_MODE="full"
  echo "[webdav] 已开启原图磁盘缓存：${VFS_CACHE_DIR}（上限 ${RCLONE_VFS_CACHE_MAX_SIZE}，自动淘汰）"
fi

mkdir -p /etc/rclone /photoprism/storage "${MOUNT_ROOT}" "${VFS_CACHE_DIR}"

# 生成 rclone 配置；密码用 rclone obscure 混淆存储
cat > /etc/rclone/rclone.conf <<EOF
[remote]
type = webdav
vendor = other
url = ${WEBDAV_URL}
user = ${WEBDAV_USER}
pass = $(rclone obscure "${WEBDAV_PASS}")
EOF

mount_one() {
  local spec="$1" remote="" name="" target="" i="" lsd_opts=""
  # 去掉首尾空白
  read -r spec <<< "${spec}"
  [[ -n "${spec}" && "${spec}" != \#* ]] || return 0

  if [[ "${spec}" == *:* ]]; then
    remote="${spec%%:*}"
    name="${spec#*:}"
  else
    remote="${spec}"
    name="$(basename "${spec}")"
  fi
  remote="${remote#/}"
  name="${name#/}"
  name="${name%/}"

  if [[ -z "${remote}" || -z "${name}" || "${name}" == */* || "${name}" == "." || "${name}" == ".." ]]; then
    echo "[webdav] 非法挂载项（应为 远程路径:挂载名）: ${spec}"
    return 1
  fi

  target="${MOUNT_ROOT}/${name}"
  mkdir -p "${target}"

  echo "[webdav] 挂载 remote:${remote} -> ${target}（只读）"
  rclone mount "remote:${remote}" "${target}" \
    --config /etc/rclone/rclone.conf \
    --allow-other \
    --read-only \
    --dir-cache-time 30s \
    --contimeout "${RCLONE_CONTIMEOUT}" \
    --timeout "${RCLONE_TIMEOUT}" \
    --retries "${RCLONE_RETRIES}" \
    --low-level-retries "${RCLONE_LOW_LEVEL_RETRIES}" \
    --vfs-cache-mode "${VFS_MODE}" \
    --vfs-cache-dir "${VFS_CACHE_DIR}" \
    --vfs-cache-max-size "${RCLONE_VFS_CACHE_MAX_SIZE}" \
    --daemon \
    --log-file "${LOG_FILE}" \
    --log-level INFO || {
      echo "[webdav] ${name} 挂载失败，详见: ${LOG_FILE}"
      return 1
    }

  # 就绪检查：探测命令本身也限时，避免 Alist 假死时卡住
  lsd_opts="--config /etc/rclone/rclone.conf --contimeout 5s --timeout 15s --low-level-retries 1"
  for i in $(seq 1 15); do
    if rclone lsd "remote:${remote}" ${lsd_opts} >/dev/null 2>&1 && mountpoint -q "${target}"; then
      echo "[webdav] ${name} 就绪（第 ${i} 次探测成功）"
      return 0
    fi
    if [[ "${i}" -eq 15 ]]; then
      echo "[webdav] ${name} 多次探测仍未就绪，退出（restart: unless-stopped 会自动重试）"
      return 1
    fi
    sleep 2
  done
}

# 分号分隔 -> 逐行处理
SPEC_TEXT="$(printf '%s' "${WEBDAV_MOUNTS}" | tr ';' '\n')"
mapfile -t SPEC_LIST <<< "${SPEC_TEXT}"

for spec in "${SPEC_LIST[@]}"; do
  mount_one "${spec}" || exit 1
done

echo "[webdav] 全部目录就绪，originals 内容："
ls -A "${MOUNT_ROOT}"
echo "[webdav] 移交 PhotoPrism 启动: $*"
exec "$@"