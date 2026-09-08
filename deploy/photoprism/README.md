# 服务器部署教程

> 新装一台 Ubuntu 服务器，**只需要 compose.yaml 和 .env 两个文件**。
> 镜像已预构建在 ghcr.io/dannisjay/photoprism-webdav:latest（amd64 + arm64），
> docker compose up -d 会自动拉取，不用自己编译、不用 clone。

## 0. 前置

```bash
# 装 Docker（含 compose 插件）
curl -fsSL https://get.docker.com | sh
```

安全组 / 防火墙放行 **2342** 端口。

## 1. 建目录

```bash
mkdir -p /opt/photoprism && cd /opt/photoprism
```

## 2. 创建 compose.yaml（内容如下，原样粘贴）
```yaml
# /opt/photoprism/compose.yaml
name: photoprism

services:
  photoprism:
    image: ghcr.io/dannisjay/photoprism-webdav:latest
    restart: unless-stopped
    privileged: true
    ports:
      - "2342:2342"
    environment:
      # ---- WebDAV 源（你的 Alist）----
      WEBDAV_URL: "${WEBDAV_URL}"
      WEBDAV_USER: "${WEBDAV_USER}"
      WEBDAV_PASS: "${WEBDAV_PASS}"
      WEBDAV_MOUNTS: "${WEBDAV_MOUNTS:-}"
      WEBDAV_SKIP_MOUNT: "${WEBDAV_SKIP_MOUNT:-false}"
      # ---- rclone 容错/缓存 ----
      RCLONE_VFS_CACHE: "${RCLONE_VFS_CACHE:-true}"
      RCLONE_VFS_CACHE_MAX_SIZE: "${RCLONE_VFS_CACHE_MAX_SIZE:-50G}"
      RCLONE_CONTIMEOUT: "${RCLONE_CONTIMEOUT:-10s}"
      RCLONE_TIMEOUT: "${RCLONE_TIMEOUT:-5m}"
      RCLONE_RETRIES: "${RCLONE_RETRIES:-3}"
      RCLONE_LOW_LEVEL_RETRIES: "${RCLONE_LOW_LEVEL_RETRIES:-20}"
      # ---- PhotoPrism ----
      PHOTOPRISM_SITE_URL: "${PHOTOPRISM_SITE_URL:-http://localhost:2342/}"
      PHOTOPRISM_ADMIN_PASSWORD: "${PHOTOPRISM_ADMIN_PASSWORD}"
      PHOTOPRISM_READONLY: "true"
      PHOTOPRISM_ORIGINALS_PATH: "/photoprism/originals"
      PHOTOPRISM_STORAGE_PATH: "/photoprism/storage"
      PHOTOPRISM_DISABLE_WEBDAV: "true"
      PHOTOPRISM_DATABASE_DRIVER: "mysql"
      PHOTOPRISM_DATABASE_DSN: "photoprism:${MARIADB_PASSWORD}@tcp(mariadb:3306)/photoprism?charset=utf8mb4,utf8&parseTime=true&loc=Local"
    volumes:
      - "./storage:/photoprism/storage"
    depends_on:
      mariadb:
        condition: service_healthy

  mariadb:
    image: mariadb:11
    restart: unless-stopped
    environment:
      MARIADB_AUTO_UPGRADE: "1"
      MARIADB_DATABASE: "photoprism"
      MARIADB_USER: "photoprism"
      MARIADB_PASSWORD: "${MARIADB_PASSWORD}"
      MARIADB_ROOT_PASSWORD: "${MARIADB_ROOT_PASSWORD}"
    volumes:
      - "./database:/var/lib/mysql"
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 10
```
## 3. 创建 .env 并改成你的配置

```bash
cat > .env <<'EOF'
# ============ PhotoPrism 登录 ============
# 用户名固定 admin；密码至少 8 位（admin 太短会被拒绝启动）
PHOTOPRISM_ADMIN_PASSWORD=admin123456
PHOTOPRISM_SITE_URL=http://你的服务器IP:2342/

# ============ WebDAV（Alist+115）============
WEBDAV_URL=https://你的alist域名/dav
WEBDAV_USER=alist账号
WEBDAV_PASS=alist密码
# 要扫的目录：远程路径:挂载名;远程路径:挂载名
WEBDAV_MOUNTS=眼镜:photos
WEBDAV_SKIP_MOUNT=false

# ============ MariaDB（改成自己的也行）============
MARIADB_PASSWORD=photoprism-db-pass
MARIADB_ROOT_PASSWORD=photoprism-db-root-pass

# ============ rclone（保持默认即可）============
RCLONE_VFS_CACHE=true
RCLONE_VFS_CACHE_MAX_SIZE=50G
EOF
nano .env
```
## 4. 启动

```bash
cd /opt/photoprism
docker compose up -d
docker compose logs -f photoprism
```

日志出现下面两行就是成了：

```
[webdav] 挂载 remote:眼镜 -> /photoprism/originals/photos（只读）
[webdav] photos 就绪（第 1 次探测成功）
photoprism start ... server: listening on 0.0.0.0:2342
```

浏览器打开 http://服务器IP:2342/ ，用户名 admin，密码填你 .env 里设置的。

## 5. 首次全量入库（扫网盘、生成缩略图）

```bash
cd /opt/photoprism
docker compose exec -T photoprism photoprism index
```

第一次会把网盘原图拉回来分析，**很慢，按张数从几分钟到几小时都正常**，跑完就不用再管。
日常新增照片会自动增量扫描，不用手动跑。

## WEBDAV_MOUNTS 语法（重要）

- 格式：远程路径:挂载名，多个目录用**分号 ; 分隔**
- 远程路径：Alist WebDAV 根（/dav）下的目录，**不带前导 /**，中文可以
- 挂载名：网页里显示的文件夹名，**不能含 / 和空格**，可中文
- 例子：
  ```ini
  WEBDAV_MOUNTS=眼镜:photos;家庭相册:family;2024旅游:trip2024
  ```
  会挂成 /photoprism/originals/photos、/family、/trip2024 三个目录
- 只改这一行就能加/删目录，不用重编译镜像，改完 docker compose up -d 生效

## 数据与排障

- 数据都在 /opt/photoprism/：storage/（缩略图/缓存/索引）、database/（MariaDB）
- 换服务器：整目录拷走即可，storage/ 和 database/ 一起拷就不用重新索引
- 网盘掉线：本地缩略图照常显示；原图要等重连（rclone 会自动恢复，不用重索引）
- 掉线期间**不要**跑 photoprism index --cleanup，会误删记录
- 看详细排障：仓库 docs/usage-v1.0.md