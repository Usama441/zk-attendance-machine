#!/usr/bin/env bash
# Starts the ZK Attendance app (Docker) and opens it in the browser.
set -e
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
URL="http://localhost:3000"
cd "$APP_DIR"

notify() { command -v notify-send >/dev/null 2>&1 && notify-send "ZK Attendance" "$1"; }

# Docker Desktop / daemon must be running.
if ! docker info >/dev/null 2>&1; then
  notify "Docker is not running. Please start Docker Desktop, then try again."
  command -v zenity >/dev/null 2>&1 && zenity --error --text="Docker is not running.\nStart Docker Desktop and try again." 2>/dev/null
  exit 1
fi

notify "Starting… (first run may take a moment)"
docker compose up -d

# Wait for the login page to answer 200.
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$URL/login" 2>/dev/null || true)
  [ "$code" = "200" ] && break
  sleep 1
done

xdg-open "$URL" >/dev/null 2>&1 &
notify "Ready — opening $URL"
