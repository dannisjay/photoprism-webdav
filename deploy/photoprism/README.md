# 服务器部署（ghcr 预构建镜像）
在 Ubuntu 服务器上执行：
  1. mkdir -p /opt/photoprism && cd /opt/photoprism
  2. 把本目录三个文件放进来（或 git clone 本仓库后 cd deploy/photoprism）
  3. sudo bash install.sh
  4. 编辑 /opt/photoprism/.env：
     - 先试看界面：WEBDAV_SKIP_MOUNT=true 保持默认即可
     - 正式扫 115：填 WEBDAV_URL/USER/PASS、WEBDAV_MOUNTS，WEBDAV_SKIP_MOUNT=false
     - PHOTOPRISM_ADMIN_PASSWORD 至少 8 位（用户名 admin）
  5. sudo bash install.sh 再次运行即拉镜像并启动
  6. 浏览器 http://<服务器IP>:2342/  登录 admin
数据目录：/opt/photoprism/storage（缩略图/原图缓存）、/opt/photoprism/database（索引库）