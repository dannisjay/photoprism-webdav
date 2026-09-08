# 设计 v1.0：无 CloudDrive 的网盘源 PhotoPrism

## 1. 背景与约束
- 用户自用，照片源在 115 网盘；已有自建 Alist 登录 115（提供 WebDAV）。
- 希望：PhotoPrism 直接以网盘为 originals 源；支持选择/添加多个目录；
  缩略图缓存在服务器本地；WebDAV 掉线不破坏已有浏览体验。
- 明确排除 CloudDrive2 一类"宿主机挂载工具"（其更新/重挂易换本地路径 → PhotoPrism 索引乱套）。
- Ubuntu 服务器，无桌面，全部走 Docker。

## 2. 上游事实核查（2026-09，develop 分支）
- PhotoPrism 文件访问是直接操作系统路径：os.Stat/Walk/Open + 外部命令
  （ffmpeg、exiftool、darktable、TensorFlow...）按本地路径读文件。
- 没有可插拔存储后端；官方 WebDAV 仅是"对外提供上传/下载"的服务，不是扫描源。
- 结论：Go 源码层做原生 WebDAV/115 直读 = 全链路重写，维护成本极高，不可作为 v1.0 方案。

## 3. 选定方案：镜像内嵌只读映射层（多目录）
```
115/照片 ──Alist WebDAV──┐
115/视频 ──Alist WebDAV──┼─> 容器内 rclone mount（每目录一个，只读）
                          │      ├─ /photoprism/originals/photos
                          │      └─ /photoprism/originals/videos
                          ▼
              PhotoPrism (READONLY=true)
                          │ ./storage（服务器本地盘）
                          ▼
         缩略图/预览/侧车/MariaDB  ← 断线时仍可用
```
- 宿主机零挂载、零 GUI；前置只有 Docker + /dev/fuse。
- 配置集中在 .env：WEBDAV_MOUNTS = "远程路径:挂载名;远程路径:挂载名"。
- 多目录彼此隔离：单目录故障/换路径不影响其余目录，也便于"只挂想扫的目录"。
- 挂载目标是容器内固定路径，与 Alist 更新无关（Alist 更新不换 WebDAV URL/路径）。
  只有用户主动改 .env 才会换目录，避免 CloudDrive 式"被动换路径 → 索引乱套"。

## 4. 关键配置
- 改版镜像：FROM photoprism/photoprism:<tag> + rclone + fuse3，替换 entrypoint。
- entrypoint：按 WEBDAV_MOUNTS 逐目录 rclone mount → 每目录探测就绪 →
  全部就绪才 exec 官方 photoprism start（容器启动阶段绝不会出现"空 originals"）。
- compose：privileged: true（或 /dev/fuse + SYS_ADMIN）；READONLY=true；
  ORIGINALS 容器内 /photoprism/originals；STORAGE 挂本地卷；MariaDB 走本地卷。

## 5. 行为特性（掉线 / 断网）
| 场景 | 表现 |
|---|---|
| 已生成过缩略图/预览，WebDAV 掉线 | 缩略图、预览照常显示（读本地 ./storage） |
| 掉线期间看大图/下载原图/人脸 | 失败（要读原图）；重连后自动恢复，无需重索引 |
| 启动时 WebDAV 不通 | entrypoint 等 30s，失败退出 → restart 重试；不会先启动看到空库 |
| 掉线期间新增照片 | 扫不到；重连后跑增量 index |
| 更换目录路径 | 只影响该目录；按"防乱套流程"操作（见 usage 手册第五节） |

## 6. 防索引乱套的纪律（吸取 CloudDrive 教训）
1. 稳定 Alist 存储路径/目录名（路径是文件身份一部分）；
2. WebDAV 掉线期间禁止 index --cleanup；
3. 换路径流程：停索引 → 改 .env → up -d → 就绪 → 普通 index 核对 → 再 --cleanup；
4. 定期备份 ./storage 与 ./database；
5. 只读模式保证不写坏网盘原文件。

## 7. 交付物
- docker/：Dockerfile、entrypoint-webdav.sh（多目录挂载）
- compose.yaml + .env.example：一键部署与配置入口
- scripts/：deploy.sh、index.sh、systemd 定时索引模板
- docs/：使用手册（usage-v1.0.md）、本设计文档

## 8. 常见疑问：为什么不直接"记录 Alist 链接"，而是走挂载？
想法：照片记录里直接存 Alist 的固定路径（如 /dav/115/照片/xx.jpg），挂载怎么变都不怕。
- PhotoPrism 内部**不存 URL/绝对路径**：媒体记录 = originals 下的**相对路径**（photos/2023/…/xx.jpg）
  + **内容 SHA1 哈希** + 文件 UID。展示、下载、缩略图、人脸全部按"originals 根 + 相对路径"
  打开本地文件，再交给 ffmpeg/exiftool/TensorFlow 等外部程序——这些程序只认本地路径。
- 所以"只存链接"= 要重写存储层、数据库模型、缩略图/原图/下载/人脸整条链路，
  等于把上游全重写（见第 2 节结论），不可维护。
- 但"乱套"的根因不是"存了绝对路径"，而是**同一相对路径下的目录树变了**
  （CloudDrive 更新换挂载点 → 文件消失/换马甲重来 → 旧记录全变孤儿）。
- 本方案用固定三层对应关系保证树不变：
  originals 根固定(/photoprism/originals) → 挂载名固定(photos) → Alist 路径固定(115/照片)。
  Alist 更新/重启、115 重登、rclone 重挂都不改变这棵树的相对路径与内容 → 索引不乱。
  等价于你想要的"以 Alist 路径为稳定身份"，只是由 FUSE 层把 URL 空间透明翻译成了路径空间。
- 代价与对策：真正"换目录"时（改 .env 挂载名）要按第 6 节流程走；
  掉线期间不跑 index --cleanup；定期备份 ./storage 与 ./database。