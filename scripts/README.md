# scripts/ —— 部署与运维

- deploy.sh：首次部署/升级（复制 .env → docker compose up -d --build）
- index.sh：手动增量入库（`scripts/index.sh --cleanup`）
- systemd/：每日定时增量索引（服务文件里 WorkingDirectory 需改成实际工程路径）
  安装：
  sudo cp scripts/systemd/photoprism-index.service scripts/systemd/photoprism-index.timer /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now photoprism-index.timer