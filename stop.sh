#!/usr/bin/env bash
# Stops the ZK Attendance app containers (data is kept).
cd "$(cd "$(dirname "$0")" && pwd)"
docker compose down
command -v notify-send >/dev/null 2>&1 && notify-send "ZK Attendance" "Stopped."
