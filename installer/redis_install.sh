#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:-/root/telegram-saas}"

if [ ! -f "$APP_DIR/config.json" ]; then
  echo "config.json not found at $APP_DIR"
  exit 1
fi

echo "Installing Redis..."
apt-get update -y
apt-get install -y redis-server

mapfile -t _redis_vals < <(python3 - <<PY
import json
path = "$APP_DIR/config.json"
cfg = json.load(open(path, "r", encoding="utf-8"))
r = cfg.get("redis", {}) or {}
print(str(r.get("enabled", False)).lower())
print(r.get("host", "127.0.0.1"))
print(r.get("port", 6379))
print(r.get("password", ""))
PY
)

redis_enabled="${_redis_vals[0]}"
redis_host="${_redis_vals[1]}"
redis_port="${_redis_vals[2]}"
redis_pass="${_redis_vals[3]}"

if [ "$redis_enabled" != "true" ]; then
  echo "Redis disabled in config.json. Skipping Redis config."
  exit 0
fi

if [ -z "$redis_pass" ]; then
  redis_pass="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"
  python3 - <<PY
import json
path = "$APP_DIR/config.json"
cfg = json.load(open(path, "r", encoding="utf-8"))
cfg.setdefault("redis", {})
cfg["redis"]["password"] = "$redis_pass"
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
PY
  echo "Generated Redis password and saved to config.json."
fi

conf="/etc/redis/redis.conf"
set_conf() {
  local key="$1"
  local value="$2"
  if grep -qE "^[#[:space:]]*${key}[[:space:]]" "$conf"; then
    sed -i "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$conf"
  else
    echo "${key} ${value}" >> "$conf"
  fi
}

set_conf "bind" "127.0.0.1"
set_conf "protected-mode" "yes"
set_conf "port" "$redis_port"
set_conf "appendonly" "yes"
set_conf "appendfsync" "everysec"
set_conf "requirepass" "$redis_pass"

systemctl enable --now redis-server
systemctl restart redis-server
echo "Redis installed and configured."
