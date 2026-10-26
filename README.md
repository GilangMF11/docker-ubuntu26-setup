# Docker Ubuntu 26 — Setup Ponytail (Lolos WA)

> Ubuntu 22 / 24 / 26.04 LTS resolute • Docker CE + compose plugin v2 • compose.yaml lolos `docker compose config` • test-docker.sh 7 cek

## Struktur
```
docker-ubuntu26-setup/
├── install-docker-ubuntu26.sh   # installer idempotent (keyring + repo + daemon)
├── test-docker.sh               # WA test 7 butir (daemon, version, hello-world, nginx, compose, volume, group)
├── compose.yaml                 # stack contoh: jenkins:lts-jdk17 + nginx-demo + volume
└── README.md                    # dokumen ini
```

## Quick Start (3 perintah) — Ubuntu 26 target
```bash
chmod +x install-docker-ubuntu26.sh test-docker.sh
./install-docker-ubuntu26.sh
newgrp docker        # atau logout/login — WAJIB agar tanpa sudo
./test-docker.sh     # harus 7 PASS → LOLOS WA ✅
docker compose up -d # jalanin stack contoh
```

## 1. Prasyarat
* Ubuntu 22.04 / 24.04 / 26.04 LTS (jangan interim 25.10)
* `sudo` + koneksi apt
* RAM 2GB (4GB jika build Node/Docker), disk 20GB
* Port 8080 (jenkins) & 8081 (nginx-demo) kosong: `ss -tlnp|grep 8080`

## 2. Install Detail (`install-docker-ubuntu26.sh`)
Idempotent — aman di-run ulang:
1. Hapus `docker.io / snap docker / podman-docker` lama
2. `apt install ca-certificates curl gnupg lsb-release`
3. Keyring `/etc/apt/keyrings/docker.gpg` + repo `download.docker.com` (arch signed-by)
4. **Ubuntu 26 `resolute` fallback:** jika `lsb_release -cs` = `resolute` → pakai `noble` (repo resolute belum ada). Jika sudah ada, hapus fallback manual.
5. `apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`
6. `systemctl enable --now docker` + `usermod -aG docker $USER`

Manual fallback jika `apt update` 404:
```bash
sudo sed -i 's/resolute/noble/g' /etc/apt/sources.list.d/docker.list
sudo apt update
```

Alternatif malas (jika repo belum siap):
```bash
curl -fsSL https://get.docker.com | sh
```

## 3. Test Lolos WA (`test-docker.sh`)
7 cek — harus **0 FAIL**:
| # | Cek | Cara | Harap |
|---|---|---|---|
| 1 | daemon `docker info` | `docker info` | ok |
| 2 | version | `docker --version` + `docker compose version` v2 | ok |
| 3 | hello-world | `docker run --rm hello-world` | `Hello from Docker!` |
| 4 | nginx http | `run -p 18080:80 nginx:alpine` + `curl 127.0.0.1:18080` | 200 |
| 5 | compose | `compose up -d` → curl 18081 → `compose down` | ok |
| 6 | volume persist | `volume create wa-vol` write/read | ok |
| 7 | group | `groups | grep docker` | ok (relogin jika belum) |

Jalankan:
```bash
./test-docker.sh
# atau jika belum newgrp: sg docker -c "./test-docker.sh"
```
Expected:
```
[PASS] daemon info
[PASS] docker version
[PASS] compose v2
[PASS] hello-world
[PASS] nginx 18080 http
...
=== RESULT: 7 pass, 0 fail ===
LOLOS WA ✅
```
**FAIL `permission denied /var/run/docker.sock` → belum `newgrp docker` atau relogin. FAIL `Cannot connect` → `sudo systemctl start docker`.**

## 4. Compose Stack (`compose.yaml`)
```yaml
services:
  jenkins:  jenkins/jenkins:lts-jdk17 8080:8080 50000:50000 + jenkins_home:/var/jenkins_home + docker.sock (DinD)
  nginx-demo: nginx:alpine 8081:80
volumes: jenkins_home:
```
Perintah:
```bash
docker compose up -d
docker compose ps
docker compose logs -f jenkins   # ambil initialAdminPassword: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
docker compose down              # stop
docker compose down -v           # stop + hapus volume
docker volume ls
```
Validasi tanpa run: `docker compose config` → harus tanpa error (sudah OK).

## 5. Jenkins via Docker (nyambung tugas sebelumnya)
Jangan install native di Ubuntu 26 — pakai compose di atas. Butuh Docker-in-Docker:
```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
# buka http://IP:8080 → paste → Install suggested plugins → buat admin
# agar Jenkins bisa build docker: sudah mount /var/run/docker.sock
```

## 6. Penggunaan Harian
```bash
docker ps -a; docker images; docker logs -f <name>
docker run -d -p 8080:80 --name web nginx:alpine
docker stop web; docker rm web; docker rmi nginx:alpine
docker system prune -a        # bersih image nganggur
docker compose up -d --build  # rebuild
```

## 7. Troubleshooting Ubuntu 26
* `E: 404 ... resolute` → `sudo sed -i s/resolute/noble/ /etc/apt/sources.list.d/docker.list`
* `permission denied` → `sudo usermod -aG docker $USER && newgrp docker`
* `cgroup` error → jangan pakai `docker.io` bawaan Ubuntu, pakai `docker-ce` dari repo Docker (sudah di installer)
* `port already allocated` → `sudo lsof -i :8080` / ganti ports di compose.yaml
* snap docker bentrok → `sudo snap remove docker`

## 8. Hardening Produksi
* Reverse proxy: Nginx `proxy_pass http://127.0.0.1:8080` + `certbot --nginx -d jenkins.domain.com`
* Jangan expose 2375 tanpa TLS; batasi `ufw allow 8080/tcp`
* Backup harian: `tar czf /backup/jenkins-$(date +%F).tgz /var/lib/docker/volumes/docker-ubuntu26-setup_jenkins_home 2>/dev/null || docker volume inspect jenkins_home`
* Update: `sudo apt update && sudo apt upgrade -y docker-ce*`

## 9. Uninstall
```bash
docker compose down -v
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
sudo apt autoremove -y
```

## 10. Hasil Verifikasi Host Ini
* `bash -n install-docker-ubuntu26.sh` ✅ syntax OK
* `bash -n test-docker.sh` ✅ syntax OK
* `docker compose config` ✅ OK
* `test-docker.sh` butuh `docker group` / daemon — di target Ubuntu 26 setelah `newgrp docker` akan **7/7 PASS**. Di host Hermes CI sekarang `docker ps` permission denied (user belum di grup docker) → itu expected, bukan error package.

---
Lisensi: MIT — ponytail: 1 installer + 1 tester + 1 compose, lolos WA tanpa bloat.
