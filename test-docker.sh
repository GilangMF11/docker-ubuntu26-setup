#!/usr/bin/env bash
# test-docker.sh — lolos WA: cek docker runnable & net & volume & compose
set -euo pipefail
PASS=0; FAIL=0
ok(){ echo "[PASS] $1"; PASS=$((PASS+1)); }
fail(){ echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== DOCKER WA TEST ==="
echo ""

# pakai sudo fallback jika grup docker belum aktif
D="docker"; $D ps >/dev/null 2>&1 || D="sudo docker"

# 1. daemon
if $D info >/dev/null 2>&1; then ok "daemon info"; else fail "daemon info"; fi

# 2. version
if $D --version|grep -q "Docker version"; then ok "docker version"; else fail "docker version"; fi
if $D compose version|grep -q "v2"; then ok "compose v2"; else fail "compose v2"; fi

# 3. hello-world
if $D run --rm hello-world 2>&1 | grep -q "Hello from Docker"; then ok "hello-world"; else fail "hello-world"; fi

# 4. nginx port 18080 (hindari bentrok 8080)
$D rm -f wa-nginx 2>/dev/null || true
$D run -d --name wa-nginx -p 18080:80 nginx:alpine >/dev/null
sleep 3
if curl -s http://127.0.0.1:18080 | grep -qi "nginx\|Welcome"; then ok "nginx 18080 http"; else fail "nginx 18080 http"; fi
$D stop wa-nginx >/dev/null; $D rm wa-nginx >/dev/null; ok "nginx cleanup"

# 5. compose up/down
mkdir -p /tmp/wa-compose && cat >/tmp/wa-compose/compose.yaml <<'Y'
services:
  web:
    image: nginx:alpine
    ports: ["18081:80"]
Y
(cd /tmp/wa-compose && $D compose up -d >/dev/null && sleep 3 && curl -s http://127.0.0.1:18081 | grep -qi "nginx" && ok "compose up 18081" || fail "compose up 18081"; $D compose down >/dev/null && ok "compose down" || fail "compose down")

# 6. volume persist
$D volume create wa-vol >/dev/null 2>&1 || true
$D run --rm -v wa-vol:/data alpine sh -c 'echo ok > /data/x' >/dev/null
if $D run --rm -v wa-vol:/data alpine cat /data/x 2>&1 | grep -q ok; then ok "volume persist"; else fail "volume persist"; fi
$D volume rm wa-vol >/dev/null 2>&1 || true

# 7. non-root
if groups | grep -q docker; then ok "user in docker group (relogin jika belum)"; else fail "user NOT in docker group — jalankan: newgrp docker atau relogin"; fi

echo ""
echo "=== RESULT: $PASS pass, $FAIL fail ==="
[[ $FAIL -eq 0 ]] && echo "LOLOS WA ✅" && exit 0 || echo "WA GAGAL — perbaiki FAIL di atas" && exit 1
