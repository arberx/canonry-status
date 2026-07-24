#!/bin/bash
# Publishes a sanitized public snapshot from the independent Mac watchdog.
set -euo pipefail

REPO="${CANONRY_STATUS_REPO:-$HOME/canonry-status}"
STATE_DIR="${CANONRY_WATCHDOG_STATE_DIR:-$HOME/canonry-watchdog/state}"
PUBLISH_INTERVAL="${CANONRY_STATUS_PUBLISH_INTERVAL:-300}"
SIGNATURE_FILE="$STATE_DIR/public-status.signature"
PUBLISHED_AT_FILE="$STATE_DIR/public-status.published-at"

CHECK_IDS=(ads-health ads-landing embedded-health embedded-landing canonry-home engine)
CHECK_LABELS=("Canonry Ads API" "Canonry Ads" "Canonry Embed API" "Canonry Embed" "Canonry Home" "Canonry Engine")

failures_for() {
  local value
  value="$(cat "$STATE_DIR/$1" 2>/dev/null || printf '0')"
  case "$value" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$value" ;;
  esac
}

status_for() {
  case "$1" in
    0) printf 'operational' ;;
    1|2) printf 'investigating' ;;
    *) printf 'outage' ;;
  esac
}

if [ ! -d "$REPO/.git" ]; then
  echo "status repository is unavailable: $REPO" >&2
  exit 1
fi

signature=""
overall="operational"
for id in "${CHECK_IDS[@]}"; do
  failures="$(failures_for "$id")"
  status="$(status_for "$failures")"
  signature+="$id=$status;"
  [ "$status" = "investigating" ] && [ "$overall" = "operational" ] && overall="investigating"
  [ "$status" = "outage" ] && overall="outage"
done

now_epoch="$(date +%s)"
last_signature="$(cat "$SIGNATURE_FILE" 2>/dev/null || true)"
last_published="$(cat "$PUBLISHED_AT_FILE" 2>/dev/null || printf '0')"
case "$last_published" in ''|*[!0-9]*) last_published=0 ;; esac

if [ "$signature" = "$last_signature" ] && [ $((now_epoch - last_published)) -lt "$PUBLISH_INTERVAL" ]; then
  exit 0
fi

git -C "$REPO" pull --ff-only --quiet

tmp="$(mktemp "$REPO/site/.status.json.XXXXXX")"
{
  printf '{\n  "schemaVersion": 1,\n'
  printf '  "updatedAt": "%s",\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '  "overall": "%s",\n' "$overall"
  printf '  "checks": [\n'
  for index in "${!CHECK_IDS[@]}"; do
    id="${CHECK_IDS[$index]}"
    failures="$(failures_for "$id")"
    status="$(status_for "$failures")"
    comma=","; [ "$index" -eq $((${#CHECK_IDS[@]} - 1)) ] && comma=""
    printf '    {"id":"%s","label":"%s","status":"%s"}%s\n' "$id" "${CHECK_LABELS[$index]}" "$status" "$comma"
  done
  printf '  ]\n}\n'
} > "$tmp"
mv "$tmp" "$REPO/site/status.json"

git -C "$REPO" add site/status.json
if git -C "$REPO" diff --cached --quiet; then
  printf '%s' "$signature" > "$SIGNATURE_FILE"
  printf '%s' "$now_epoch" > "$PUBLISHED_AT_FILE"
  exit 0
fi

git -C "$REPO" -c user.name="Canonry Status Watchdog" -c user.email="status-bot@canonry.ai" commit --quiet -m "status: publish snapshot"
git -C "$REPO" push --quiet origin main
printf '%s' "$signature" > "$SIGNATURE_FILE"
printf '%s' "$now_epoch" > "$PUBLISHED_AT_FILE"
