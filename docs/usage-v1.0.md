# 使用手册 v1.0（Ubuntu Server）

## 一、部署（已装 Docker）
1. 把整个工程传到服务器，例如 /opt/photoprism-1.0
2. cd /opt/photoprism-1.0 && bash scripts/deploy.sh
   （首次会生成 .env，按要求编辑后再跑一次）
3. docker compose ps          # 两个容器 healthy/up
4. 浏览器打开 http://服务器IP:2342/ 用 .env 的 PHOTOPRISM_ADMIN_PASSWORD 登录

## 二、选择要扫描的目录（支持多个）
配置只在工程根目录 .env 的 WEBDAV_MOUNTS，格式：
  远程路径:挂载名;远程路径:挂载名
- 远程路径 = 在 Alist 网页界面看到的路径，去掉前导 /：
  例：115 挂在 Alist 的 /115，要扫 /115/照片 → 写 115/照片
- 挂载名 = 你在 PhotoPrism 里看到的文件夹名（自己起，字母数字，不能含 /）
- 例：WEBDAV_MOUNTS=115/照片:photos;115/视频:videos
- 不写挂载名则自动取目录最后一段：115/照片;115/视频
- 只挂想扫的目录；挂载之间互相隔离，一个目录出问题不影响其他目录
- 以后加减目录：改这一行 → docker compose up -d → 重新索引即可（不用重编译镜像）

## 三、扫描入库
- 自动：容器启动约 5 分钟后自动索引一次（PHOTOPRISM_AUTO_INDEX=300）；
- 手动：docker compose exec photoprism photoprism index
  或 bash scripts/index.sh（--cleanup 会清理"已删除文件"的记录）；
- 定期：安装 systemd 定时器（见 scripts/README.md），默认每天 03:30 增量索引。
- 进度：docker compose logs -f photoprism 或网页右上角进度条。

## 四、Alist/网盘掉线时会怎样（重要）
- 已生成的缩略图、预览图都存在服务器 ./storage，**不依赖网盘**：
  掉线后已浏览过的照片缩略图、预览照常显示；
- 点开"看大图/下载原图/人脸识别"需要临时读网盘原图 → 掉线期间会失败/报错，
  **重新连上后自动恢复，不需要重新索引**（索引记录都还在）；
- 掉线期间新上传到网盘的照片当然扫不到，重连后跑一次增量 index 即可；
- 容器启动时如果 WebDAV 连不上：entrypoint 会等 30 秒，仍失败则退出并自动重启重试，
  不会出现"PhotoPrism 先启动、看到空目录"的情况。

## 五、防"路径丢失后全部乱套"的纪律（CloudDrive 的教训）
PhotoPrism 按"文件身份"记录索引。CloudDrive 更新后换了本地挂载路径，
相当于所有文件"消失+换个马甲重来"，旧记录全变孤儿 → 界面乱套。
本方案里挂载点是容器内固定路径，来源是 Alist 的 WebDAV 地址，Alist 更新不影响；但仍请遵守：
1. **不要随便改 Alist 里的存储路径/目录名**；路径是索引的身份之一；
2. **Alist 或网盘掉线时，绝不执行 index --cleanup**（会把暂时看不到的文件当"已删除"清掉记录）；
   只有确认当前挂载内容完整无误时才用 --cleanup；
3. 万一真要整体换路径：停索引 → 改 .env → up -d 等挂载就绪 → 先跑普通 index 核对 →
   确认照片没少、没重复，再跑一次 index --cleanup；
4. 定期备份 ./storage（索引库+缩略图）与 ./database（MariaDB），出问题可整体回滚；
5. 只读模式 + 多目录隔离，已经保证：任何一个网盘目录出问题，不写坏原文件、不影响别的目录。

## 六、首次全量索引注意事项
- 会逐张读取网盘原图（缩略图/人脸用），受 115 速率限制，几万张可能跑数小时到数天；
- 建议先在 WEBDAV_MOUNTS 里只指一个小相册跑通，再扩到整库；
- 服务器建议 ≥4GB 内存 + ≥4GB swap，storage 目录用本地 SSD。

## 七、故障排查
- 挂载失败：docker compose logs photoprism，看 [webdav] 行与 /photoprism/storage/rclone.log；
- 401/403：Alist 账号密码错，或该账号无权访问该路径；先浏览器登 Alist 验证；
- 某个目录没扫到：核对 WEBDAV_MOUNTS 里远程路径与 Alist 界面一致；手动跑一次 index；
- 容器反复重启：多半是 Alist 地址从容器里不通——WEBDAV_URL 用内网 IP：
  docker compose exec photoprism curl -I http://<IP>:5244/dav

## 附：机制说明 —— Alist 不是本地磁盘，它是怎么变成路径的？

### 管道长在容器里，不在宿主机
```
你的服务器/路由器/NAS 上：  Alist(115)  →  http://IP:5244/dav  （一个网络服务，不是磁盘）

改版容器内部（每次启动 entrypoint 自动执行）：
   rclone mount  http://IP:5244/dav/115/照片  ──FUSE──>  /photoprism/originals/photos

PhotoPrism 看到的：一个普通本地目录 /photoprism/originals/photos
实际发生：每次读文件，rclone 实时向 Alist 发请求拉取
```
- FUSE = Linux 的"用户态文件系统"：让一个网络地址在容器内部"看起来像本地文件夹"。
- 这段翻译管道**由容器自己建立**，宿主机上不需要装、不需要常驻任何 CloudDrive/rclone 进程。

### 重启后为什么不会"路径丢失"（对比 CloudDrive）
- CloudDrive 乱套的流程：宿主机重启 → CloudDrive 客户端没自启/重挂失败 →
  它原来霸占的那个宿主目录空了 → PhotoPrism 绑定的目录=空 → 索引全变孤儿。
- 我们的流程：容器每次启动，entrypoint **先**执行挂载并逐目录探测，
  **全部就绪后才启动 PhotoPrism**；探测失败就退出，`restart: unless-stopped` 自动重试。
  所以每次重启 = 标准流程"重建管道 → 建好才开门"，不存在"PhotoPrism 先跑起来对着空目录扫"。
  索引记录在本地 ./storage，重启不丢。
- 如果 Alist 也是容器：给它也配 `restart: unless-stopped`；就算它比 PhotoPrism 晚起，
  由上面的就绪探测兜底（最多等 30 秒/次，反复重试直到 Alist 可连）。

### Alist 连接超时/断线会怎样
- 挂载建立之后 Alist 失联：
  - 已生成过的缩略图/预览照常显示（它们存在本地 ./storage，不碰网盘）；
  - 需要读原图的操作（看大图、下载、人脸识别、扫描新文件）会报错或一直转圈；
  - rclone 会自动重试，**Alist 恢复后这些操作自动恢复**，不用重启容器，索引记录无损。
- 长时间失联导致挂载假死：重启容器即可，entrypoint 会重新挂载，不会以空目录状态启动。
- 唯一能搞乱库的操作仍然只有一条：**断线期间手动跑 `index --cleanup`**——所以规则不变：断线不清理。

## 附：已内置的"抗断线"加固（v1.0 更新）
- 超时与重试：rclone 挂载带 `--contimeout 10s --timeout 5m --retries 3 --low-level-retries 20`，
  瞬时抖动/慢响应会自动重试而不是立刻报错；就绪探测命令也限时，Alist 假死不会卡住启动。
  均可通过 .env 的 RCLONE_CONTIMEOUT / RCLONE_TIMEOUT / RCLONE_RETRIES / RCLONE_LOW_LEVEL_RETRIES 调整。
- 原图磁盘缓存（默认开）：`RCLONE_VFS_CACHE=true`，看过的原图会落到服务器本地
  `./storage/rclone-vfs`（上限 `RCLONE_VFS_CACHE_MAX_SIZE=50G`，超出自动淘汰最旧的）。
  效果：Alist 断线时，**看过的照片仍能看大图**（无需重连）；新文件首次打开仍需联网。
  代价：额外占用本地磁盘，按实际磁盘空间调小/调大；不想用可设 `RCLONE_VFS_CACHE=false`。

## 附：MariaDB 是什么？
- MariaDB = MySQL 的开源分支（兼容替代品），一个**数据库服务**。
- PhotoPrism 用它存"索引记录"：哪张照片、相对路径、内容哈希、拍摄时间、标签、相册、人物关系……
  不是图片文件本身（图片仍只在 115 网盘）。
- 本工程里它和 PhotoPrism 是两个容器：photoprism 容器负责扫描/展示，mariadb 容器负责记索引，
  数据落在宿主机 `./database` 目录；`./storage` 是 PhotoPrism 自己的工作目录
  （缩略图、原图缓存 rclone-vfs、侧车、日志）。
- 影响：`./database` 是"索引"的命根子——删了它=所有记录/相册/人脸标注清空（照片在网盘没动，
  可重新全量索引重建）；所以备份要同时覆盖 `./database` 与 `./storage`。