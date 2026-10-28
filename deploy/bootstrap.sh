#!/usr/bin/env bash
# EC2(Ubuntu 24.04 arm64) 첫 준비. ubuntu 사용자로 한 번 실행한다(여러 번 실행해도 된다).
#   bash bootstrap.sh
# 하는 일: 시간대, 스왑 2GB, Docker, fail2ban(sshd), SSH 비밀번호 로그인 끄기 확인, /opt/remine, 백업 cron
set -euo pipefail

# 시간대: cron(백업 04:00)을 한국 시각으로. 서버 앱은 이와 무관하게 Asia/Seoul로 고정돼 있다.
sudo timedatectl set-timezone Asia/Seoul

# 스왑 2GB: 1GB 인스턴스에서 JVM + PostgreSQL + Caddy가 순간적으로 넘칠 때 OOM 대신 스왑을 쓴다.
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-remine-swap.conf
  sudo sysctl --system > /dev/null
fi

# Docker (공식 apt 저장소)
if ! command -v docker > /dev/null; then
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  echo "docker 그룹 적용: 한 번 로그아웃 후 다시 접속하세요."
fi

# fail2ban: 22 포트가 전체에 열려 있으니(Actions 러너 IP가 매번 달라서) 반복 실패 IP를 1시간 차단한다.
sudo apt-get install -y fail2ban python3-systemd
sudo tee /etc/fail2ban/jail.d/remine-sshd.local > /dev/null <<'JAIL'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
JAIL
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban

# SSH 비밀번호 로그인 꺼짐 확인. sshd_config.d는 먼저 읽은 값이 이기므로 00- 이름으로 둔다.
if ! sudo sshd -T | grep -qx 'passwordauthentication no'; then
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/00-remine.conf > /dev/null
  sudo sshd -t
  sudo systemctl reload ssh
fi
sudo sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication) '

# 배포 폴더. compose.yaml·Caddyfile·backup.sh는 Actions가 복사하고, .env·secrets/는 직접 올린다.
sudo mkdir -p /opt/remine/secrets /opt/remine/backups
sudo chown -R "$USER":"$USER" /opt/remine
chmod 700 /opt/remine/secrets

# 백업 cron: 매일 04:00 (중복 등록 방지)
line='0 4 * * * /opt/remine/backup.sh >> /opt/remine/backups/backup.log 2>&1'
( crontab -l 2>/dev/null | grep -vF '/opt/remine/backup.sh'; echo "$line" ) | crontab -

cat <<'NEXT'
완료. 다음:
  1) PC에서 키 올리기: scp remine.env(.env 형식) → /opt/remine/.env, firebase-admin.json → /opt/remine/secrets/
  2) 서버에서 권한: chmod 600 /opt/remine/.env
                    sudo chown 10001:10001 /opt/remine/secrets/firebase-admin.json && sudo chmod 400 /opt/remine/secrets/firebase-admin.json
  3) 배포 전용 공개키를 ~/.ssh/authorized_keys에 추가
NEXT
