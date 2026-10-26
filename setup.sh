#!/usr/bin/env bash
# setup.sh — 1-click: install docker + test WA + compose up + jenkins ready (Ubuntu 22/24/26)
set -euo pipefail
cd "$(dirname "$0")"

say(){ echo -e "\n\033[1;36m==>\033[0m $1"; }
ok(){ echo -e "\033[1;32m[OK]\033[0m $1"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $1"; }
fail(){ echo -e "\033[1;31m[FAIL]\033[0m $1"; }

say "Cek OS"
cat /etc/os-release 2>/dev/null | grep -E "PRETTY_NAME|VERSION" || true
lsb_release -a 2>/dev/null | head -5 || true

say "[1/5] Install Docker CE"
chmod +x install-docker-ubuntu26.sh test-docker.sh
./install-docker-ubuntu26.sh

say "[2/5] Aktifkan grup docker (tanpa relogin jika baru)"
if groups 2>/dev/null | grep -qw docker; then
  ok "user sudah di grup docker"
  D="docker"
else
  warn "user belum di grup docker — coba sg docker (tanpa relogin)"
  if sg docker -c "docker ps" >/dev/null 2>&1; then
    ok "sg docker OK — test akan pakai sg docker"
    D="sg docker -c docker"
  else
    warn "sg docker belum OK, akan pakai sudo docker fallback untuk test"
    D="sudo docker"
  fi
  echo "TIP: setelah ini jalankan 'newgrp docker' atau logout/login agar docker tanpa sudo permanen"
fi

say "[3/5] Test WA (7 cek)"
# jalankan test via wrapper agar lolos walau grup belum aktif
if groups | grep -qw docker; then
  ./test-docker.sh || { fail "WA belum lolos — cek output FAIL di atas"; exit 1; }
else
  # reroute test: pakai sg docker
  if sg docker -c "true" 2>/dev/null; then
    sg docker -c "./test-docker.sh" || { fail "WA belum lolos"; exit 1; }
  else
    # last fallback: edit test sementara pakai sudo docker
    warn "pakai sudo untuk WA (butuh NOPASSWD atau password)"
    sudo ./test-docker.sh || { fail "WA gagal — jalankan: newgrp docker && ./test-docker.sh"; exit 1; }
  fi
fi
ok "WA lolos"

say "[4/5] Compose up (jenkins + nginx-demo)"
# pilih invocation compose yang work
COMPOSE="docker compose"
if ! $D ps >/dev/null 2>&1; then
  if sg docker -c "docker ps" >/dev/null 2>&1; then
    COMPOSE="sg docker -c 'docker compose'"
    sg docker -c "docker compose -f compose.yaml up -d"
  else
    sudo docker compose -f compose.yaml up -d
    COMPOSE="sudo docker compose"
  fi
else
  if groups | grep -qw docker; then
    docker compose -f compose.yaml up -d
  else
    sg docker -c "docker compose -f compose.yaml up -d"
  fi
fi
$D ps 2>/dev/null | head -20 || sg docker -c "docker ps" 2>/dev/null | head -20 || sudo docker ps 2>/dev/null | head -20 || true

say "[5/5] Tunggu Jenkins ready http://127.0.0.1:8080/login"
for i in $(seq 1 60); do
  if curl -sf http://127.0.0.1:8080/login >/dev/null 2>&1; then ok "Jenkins UP (percobaan $i)"; break; fi
  sleep 3
  if [[ $i -eq 60 ]]; then warn "Jenkins belum 200 setelah 180s — cek: $COMPOSE logs jenkins"; fi
done

echo ""
echo "══════════════════════════════════════════"
$D ps 2>/dev/null | grep jenkins || sg docker -c "docker ps" 2>/dev/null | grep jenkins || sudo docker ps 2>/dev/null | grep jenkins || true
echo "URL: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'):8080"
echo "Ambil password awal:"
if $D ps >/dev/null 2>&1; then $D exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "(tunggu 30s lalu: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword)"
else sg docker -c "docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword" 2>/dev/null || sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
fi
echo "══════════════════════════════════════════"
echo "Next: buka URL di browser → paste password → Install suggested plugins → buat admin → baca JENKINS-OPS.md §3-§6"
echo "Log: $COMPOSE logs -f jenkins"
echo "Stop: $COMPOSE down   | Hapus data: $COMPOSE down -v"
