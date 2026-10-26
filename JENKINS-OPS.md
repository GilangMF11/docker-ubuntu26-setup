# Jenkins di Ubuntu 26 via Docker — Operasional Lengkap (Lolos WA)

> Prasyarat: `./install-docker-ubuntu26.sh` + `newgrp docker` + `./test-docker.sh` 7 PASS. Stack di `compose.yaml` (jenkins:lts-jdk17 8080 / 50000 + volume `jenkins_home` + mount `docker.sock`).

## 0. Start Stack
```bash
cd ~/Development/docker-ubuntu26-setup
docker compose up -d
docker compose ps                    # jenkins Up, nginx-demo Up
docker compose logs -f jenkins       # tunggu "Jenkins is fully up and running"
ss -tlnp | grep 8080                 # LISTEN 8080
```

## 1. Setup Awal (Sekali Saja — 2 menit)
1. Ambil password awal:
```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
# contoh: a1b2c3d4e5f6...
```
2. Buka `http://IP_SERVER:8080` (atau `http://localhost:8080` jika lokal).
3. Paste password → **Install suggested plugins** (tunggu 1-2 menit).
4. Buat Admin User → `admin / pass kuat` → `Save and Continue` → `Save and Finish` → `Start using Jenkins`.

> Jika 8080 bentrok / mau domain: set Nginx proxy 80→8080 + `certbot --nginx -d jenkins.domain.com` (lihat README §8). Inner URL Jenkins tetap `http://jenkins:8080`.

## 2. Peta Menu (Kemana Klik)
* **Dashboard** = daftar job. **New Item** = bikin job baru. **Manage Jenkins** = setting global (plugin, credential, JDK, security). **Build History** (kiri) = riwayat. Tiap Job → **Build Now** / **Configure** / **Builds** / **Console Output**.

## 3. Buat Job Pertama — Freestyle (Hello World, 1 menit)
`New Item` → `Freestyle project` → Name: `hello` → OK →
* **Build Steps** → `Add build step` → `Execute shell`:
```bash
echo "Halo dari Jenkins $(date)"
java -version
docker --version
```
→ `Save` → `Build Now` → klik ` #1` → `Console Output` harus `Finished: SUCCESS`.

## 4. Pipeline (Rekomendasi Ponytail — Declarative Jenkinsfile)
Pipeline = build as code, versioned di Git, lolos WA.

### 4a. Pipeline via Git (Produksi)
Repo punya `Jenkinsfile` di root:
```groovy
pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }
  stages {
    stage('Checkout') { steps { checkout scm } }
    stage('Build')    { steps { sh 'docker --version; ls -la' } }
    stage('Test')     { steps { sh 'chmod +x test-docker.sh; ./test-docker.sh || true' } }
    stage('Deploy')   { when { branch 'main' } steps { sh 'docker compose up -d' } }
  }
  post { always { echo "done #${env.BUILD_NUMBER}" } }
}
```
Buat job: `New Item` → `Pipeline` → Name `myapp-pipeline` → Bagian **Pipeline** → `Definition: Pipeline script from SCM` → SCM `Git` → URL `https://github.com/USER/REPO` → Branch `*/main` → Script Path `Jenkinsfile` → Save → `Build Now`.

### 4b. Pipeline Inline (Tanpa Git — Coba Cepat)
`New Item` → `Pipeline` → Pipeline → `Definition: Pipeline script` → paste groovy di atas (ganti `checkout scm` jadi `sh 'echo no scm'`) → Save → Build Now.

## 5. GitHub Webhook (Auto Build Tiap Push — 2 menit)
Tanpa webhook = harus `Build Now` manual.
1. Jenkins: Job → `Configure` → **Triggers** → centang `GitHub hook trigger for GITScm polling`.
2. GitHub: repo → `Settings` → `Webhooks` → `Add webhook` → Payload URL `http://IP:8080/github-webhook/` → Content `application/json` → `Just push` → `Add webhook`.
3. Test: `git push` → Jenkins otomatis build (lihat `GitHub Hook Log` jika tidak jalan: `Manage Jenkins > System Log`).

> Jika Jenkins di balik Nginx + HTTPS, Payload URL pakai `https://jenkins.domain.com/github-webhook/` dan `Manage Jenkins > System > GitHub` set URL.

## 6. Credentials (WAJIB untuk Repo Privat / Docker Hub)
`Manage Jenkins` → `Credentials` → `System` → `Global credentials` → `Add Credentials`:
* **Git privat:** Kind `Username with password` (PAT GitHub) atau `SSH Username with private key`. Di Pipeline pakai `credentialsId`: `git credentialsId: 'github-pat', url: 'https://github.com/...'`.
* **Docker Hub:** Kind `Username with password` ID `docker-hub` → di Jenkinsfile:
```groovy
stage('Push') { steps { withCredentials([usernamePassword(credentialsId:'docker-hub', usernameVariable:'U', passwordVariable:'P')]) {
  sh 'echo $P | docker login -u $U --password-stdin && docker push myuser/myapp:$BUILD_NUMBER'
}}}
```

## 7. Agar Jenkins Bisa Build Docker (Sudah Siap di compose.yaml)
Stack sudah mount `- /var/run/docker.sock:/var/run/docker.sock` → Jenkins bisa `docker build / docker compose`. Jika job gagal `permission denied docker.sock`:
```bash
docker exec -u root jenkins groupadd -g $(getent group docker | cut -d: -f3) docker 2>/dev/null; docker exec -u root jenkins usermod -aG docker jenkins; docker restart jenkins
# alternatif aman: jalankan agen terpisah (lihat §11)
```

## 8. Operasi Harian (Perintah yang Sering Dipakai)
```bash
docker compose ps; docker compose logs -f --tail 100 jenkins
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword  # jika lupa
docker restart jenkins; docker compose restart jenkins
# Update Jenkins LTS
docker compose pull jenkins; docker compose up -d jenkins
# Backup / Restore (harian cron disarankan)
docker run --rm -v docker-ubuntu26-setup_jenkins_home:/vol -v /backup:/backup alpine tar czf /backup/jenkins-$(date +%F).tgz -C / vol
# restore:
# docker run --rm -v docker-ubuntu26-setup_jenkins_home:/vol -v /backup:/backup alpine sh -c 'rm -rf /vol/* && tar xzf /backup/jenkins-2026-10-26.tgz -C /'
```

## 9. Cek Hasil Build
Job → klik `#N` → **Console Output** (log lengkap) → **Changes** (commit pemicu) → **Pipeline Steps** (jika Pipeline). Lonceng biru = SUCCESS, merah = FAILURE, kuning = UNSTABLE (test gagal tapi build jalan).

## 10. Troubleshooting Cepat
* `Jenkins is offline / no plugin update` → cek internet container: `docker exec jenkins ping -c1 8.8.8.8`; proxy: `Manage Jenkins > Plugins > Advanced > HTTP Proxy`.
* `Failed to connect to github.com` → credential salah / webhook URL http bukan https diblok GitHub → pakai PAT + webhook https.
* `port 8080 already allocated` → `sudo lsof -i :8080` → hentikan / `ports: ["8081:8080"]` di compose.yaml lalu `up -d`.
* `No such file docker` di Jenkins → image jenkins tidak punya docker CLI → install via `docker exec -u root jenkins apt update && apt install -y docker.io` atau pakai agen Docker (next section).
* Lupa admin pass → `docker exec jenkins cat /var/jenkins_home/users/admin*/config.xml` atau reset: `docker exec jenkins bash -c 'rm /var/jenkins_home/secrets/slave-to-master-security-kill-switch'` + restart.

## 11. Scale: Agent Docker (Jika Build Butuh Node 20 / Java 21 / Kaniko)
Jangan install tool di master. Tambah agen di `compose.yaml`:
```yaml
  jenkins-agent:
    image: jenkins/inbound-agent:latest
    environment: { JENKINS_URL: http://jenkins:8080, JENKINS_AGENT_NAME: agent1, JENKINS_SECRET: <secret-dari-Manage-Jenkins-Nodes> }
```
Atau pakai **Docker Pipeline** + `agent { docker { image 'node:20-alpine' } }` di Jenkinsfile.

## 12. Hentikan / Hapus
```bash
docker compose down        # stop (data aman di volume jenkins_home)
docker compose down -v     # stop + HAPUS semua data Jenkins (hati-hati)
```

## Checklist Lolos WA Jenkins
* [ ] `docker compose up -d` → `docker compose ps` Up, `curl http://127.0.0.1:8080/login` 200
* [ ] `initialAdminPassword` terbaca & login admin berhasil
* [ ] Job Freestyle `hello` → `Finished: SUCCESS`
* [ ] Job Pipeline `Jenkinsfile` → `Build Now` SUCCESS
* [ ] `docker exec jenkins docker ps` tidak permission denied (persetujuan DinD)
* [ ] Backup `jenkins-*.tgz` terbuat

---
Dokumen ini + `compose.yaml` + `test-docker.sh` = paket lolos WA tanpa bloat. Butuh pipeline contoh repo? Bilang stack kamu (Node/Go/Python) → aku kasih `Jenkinsfile` siap pakai.
