# syntax=docker/dockerfile:1
# =========================================================
# PhotoPrism Local v1.0（改版）
# 在官方镜像上嵌入 rclone + fuse，把 WebDAV(115/Alist) 只读
# 挂载为 /photoprism/originals。不改上游 PhotoPrism 任何代码。
# 升级上游：改 PHOTOPRISM_TAG 重新 build。
# =========================================================
ARG PHOTOPRISM_TAG=latest
# 稳定后可固定到具体版本，例如 260728：
# ARG PHOTOPRISM_TAG=260728

FROM photoprism/photoprism:${PHOTOPRISM_TAG} AS base
FROM rclone/rclone:latest AS rclone-bin
FROM base

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends fuse3 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=rclone-bin /usr/local/bin/rclone /usr/local/bin/rclone
COPY entrypoint-webdav.sh /entrypoint-webdav.sh
RUN chmod +x /entrypoint-webdav.sh

ENTRYPOINT ["/entrypoint-webdav.sh"]
CMD ["/opt/photoprism/bin/photoprism", "start"]