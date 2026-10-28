#!/usr/bin/env bash
# DB 백업: 하루 1번(cron, bootstrap.sh가 등록) pg_dump를 backups/에 남기고 7일 지난 것은 지운다.
# 복원: docker compose exec -T postgres pg_restore -U remine -d remine --clean --if-exists < backups/remine-YYYYMMDD.dump
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p backups
out="backups/remine-$(date +%Y%m%d).dump"
docker compose exec -T postgres pg_dump -Fc -U remine remine > "$out.tmp"
mv "$out.tmp" "$out"
find backups -name 'remine-*.dump' -mtime +7 -delete
echo "$(date '+%F %T') backup ok: $out ($(du -h "$out" | cut -f1))"
