#!/usr/bin/env bash
#
# session-log-retention.sh — 처리 완료된 session log 보존 정책
#
# ingested: true 로 마킹된 지 RETENTION_DAYS(파일 mtime 기준)가 지난
# session-logs/*.md 를 삭제한다. ingested: false(미처리) 로그는 절대 건드리지 않는다.
#
# 사용법:
#   session-log-retention.sh <vault-path> [days=30]
# 환경 변수:
#   GIEOK_RETENTION_DRY_RUN=1  삭제하지 않고 대상만 출력
#
set -euo pipefail

VAULT="${1:?usage: session-log-retention.sh <vault-path> [days]}"
DAYS="${2:-30}"
DIR="${VAULT}/session-logs"
LOG_PREFIX="[log-retention $(date +%Y%m%d-%H%M)]"

if [ ! -d "${DIR}" ]; then
  echo "${LOG_PREFIX} no session-logs dir at ${DIR}, skipping."
  exit 0
fi

deleted=0
skipped=0
while IFS= read -r f; do
  # frontmatter 에 ingested: true 가 있는 파일만 대상 (미처리 로그 보호)
  if /usr/bin/grep -q '^ingested: true' "$f"; then
    if [ "${GIEOK_RETENTION_DRY_RUN:-0}" = "1" ]; then
      echo "${LOG_PREFIX} DRY RUN: would delete $f"
    else
      rm -f "$f"
    fi
    deleted=$((deleted + 1))
  else
    skipped=$((skipped + 1))
  fi
done < <(/usr/bin/find "${DIR}" -maxdepth 1 -type f -name '*.md' -mtime +"${DAYS}")

echo "${LOG_PREFIX} vault=${VAULT} days=${DAYS} deleted=${deleted} kept(not-ingested)=${skipped}"
