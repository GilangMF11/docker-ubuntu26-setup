#!/usr/bin/env bash
# install-docker-ubuntu26.sh — ponytail idempotent installer Docker CE untuk Ubuntu 22/24/26
# Tested target: Ubuntu 26.04 LTS (resolute) fallback noble jika repo 404
set -euo pipefail

echo "==> [1/6] Hapus docker lama / snap / podman"
sudo snap remove docker 2>/dev/null || true
sudo apt remove -y docker.io docker-doc podman-docker containerd docker-compose 2>/dev/null || true

echo "==> [2/6] Install dependensi"
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

echo "==> [3/6] Setup keyring & repo Docker"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

CODENAME=$(lsb_release -cs)
# Ubuntu 26 resolute belum ada di download.docker.com → fallback noble
if [[ "$CODENAME" == "resolute" ]]; then
  echo "WARN: resolute belum di mirror Docker, fallback ke noble"
  CODENAME="noble"
fi

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "==> [4/6] Install Docker CE + compose plugin"
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> [5/6] Enable & start daemon"
sudo systemctl enable --now docker
sudo systemctl status docker --no-pager | head -20

echo "==> [6/6] Non-root akses"
sudo usermod -aG docker "$USER" || true
echo "OK: logout/login atau jalankan 'newgrp docker' agar tanpa sudo"

echo ""
echo "==> Verifikasi cepat"
docker --version || sudo docker --version
docker compose version || sudo docker compose version
echo "Jalankan: ./test-docker.sh untuk lolos WA"
