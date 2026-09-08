# PhotoPrism Local v1.0（改版）

> 目标：脱离 CloudDrive 类挂载工具，让 PhotoPrism 直接把 **Alist/115 网盘的 WebDAV**
> 当作 originals 只读源，**支持选择多个网盘目录**；缩略图、侧车与索引数据库全部
> 缓存/存放在服务器本地磁盘。部署目标：Ubuntu Server + Docker。

## 版本
- VERSION：`1.0`（见 VERSION）
- 上游基线：photoprism/photoprism（AGPL-3.0，自用）

## 架构（只加一层，不改上游代码）
```
Alist(115) ──WebDAV──> 容器内 rclone 逐个只读挂载
                          ├──> /photoprism/originals/photos   (115/照片)
                          └──> /photoprism/originals/videos   (115/视频)
                                          │
                              PhotoPrism (READONLY=true)
                                          │
                                   ./storage  ← 缩略图/预览/侧车/索引全在服务器本地
```
- 上游 PhotoPrism 没有"把 WebDAV 当扫描源"的选项（内置 WebDAV 是反方向提供上传），
  也没有可插拔文件系统层；所以 v1.0 采用"官方镜像外再包一层"，**不改上游一行代码**。
- 宿主机零挂载、无 CloudDrive；Alist 仍是你自己部署的（它提供 115→WebDAV）。
- 挂载点容器内固定；多目录互相隔离，一个目录出问题不影响其他目录。

## 改动文件（全部在本工程内）
| 文件 | 作用 |
|---|---|
| docker/Dockerfile | 官方镜像 + rclone + fuse3（升级=改 tag 重建） |
| docker/entrypoint-webdav.sh | 按 .env 把多个 WebDAV 目录只读挂进 originals，就绪后启动 PhotoPrism |
| compose.yaml | photoprism + mariadb，一键起 |
| .env.example | 所有配置入口（WebDAV 地址/账号/密码/要扫的目录列表） |
| scripts/deploy.sh / index.sh | 部署与手动入库 |
| scripts/systemd/ | 每日定时增量索引 |

## 快速开始
```
cp .env.example .env
# 编辑：WEBDAV_URL/USER/PASS + WEBDAV_MOUNTS（多目录，见 .env 注释）+ 管理员密码
docker compose up -d --build
docker compose exec photoprism photoprism index   # 手动入库（或等约 5 分钟自动索引）
```
浏览器：http://服务器IP:2342/

## 关键问答
- 选目录/加多个：只改 .env 的 WEBDAV_MOUNTS，加减目录不用重编译镜像；
- 网盘掉线：缩略图/预览在本地照常显示；看原图需重连（自动恢复，不用重索引）；
- 防乱套：掉线时不要跑 index --cleanup；路径稳定、定期备份 ./storage。
  详见 docs/usage-v1.0.md。

## 详细文档
- 使用手册（部署/多目录/入库/断线/排障）：docs/usage-v1.0.md
- 技术决策与风险：docs/design-v1.0.md

## 状态
- [x] Phase 1：工程骨架与设计（v1.0）
- [x] Phase 2：改版镜像（Dockerfile + entrypoint + 多目录 FUSE 挂载）
- [x] Phase 3：全栈 compose（.env 配置入口 + MariaDB + 定时索引模板）
- [ ] Phase 4：Ubuntu 真机部署验证（首次全量索引压测）

## 用 GitHub Actions 预构建镜像（可选）
- 推送到 GitHub 后，Actions 自动构建并推送 **amd64 + arm64** 双架构镜像：
  `ghcr.io/dannisjay/photoprism-webdav:1.0`（另有 latest / git-sha / v* 标签）。
- 服务器想直接拉预构建镜像（不本地编译）时，把 compose.yaml 的 photoprism 服务改成：
  ```yaml
  photoprism:
    image: ghcr.io/dannisjay/photoprism-webdav:1.0
    # 删除 build: 段
  ```
  然后 `docker compose pull && docker compose up -d`。
- 注意：`.env` 与 `./storage`、`./database` 均已被 .gitignore 排除，不会进仓库。

## 服务器快速试跑
- 现成部署包在 deploy/photoprism/（直接用 ghcr 镜像）：拷到服务器后 sudo bash install.sh，
  详情见 deploy/photoprism/README.md。
