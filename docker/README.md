# docker/ —— 改版镜像层

- Dockerfile：`FROM photoprism/photoprism:<tag>` + 嵌入 rclone、fuse3，不改上游代码。
- entrypoint-webdav.sh：启动时按 `WEBDAV_URL/USER/PASS/PATH` 用 rclone 把 WebDAV 只读
  挂到 `/photoprism/originals`，就绪后移交 `photoprism start`。
- 构建：在工程根目录执行 `docker compose up -d --build`（镜像 tag: photoprism-115:1.0）。
- 升级上游：修改 Dockerfile 顶部 `PHOTOPRISM_TAG`（建议固定如 260728）后重新 build。