#!/usr/bin/env bash
set -euo pipefail

STATE_FILE=".install_state"
DEFAULT_ZIP_URL="https://raw.githubusercontent.com/Lucasfig199/SAAS-4.0-REDIS/main/telegram-saas.zip"
DEFAULT_INSTALL_DIR="/root/telegram-saas"
DEFAULT_SERVICE_NAME="telegram-saas"
DEFAULT_PORT="5000"

GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

print_banner() {
  local blue="\033[1;34m"
  local reset="\033[0m"
  echo -e "${blue}"
  echo "=============================================================="
  echo "  ____  _____ __  __  __      ____  ___  _   _ ____   ___  "
  echo " | __ )| ____|  \\/  | \\ \\    / /  \\/ _ \\| \\ | |  _ \\ / _ \\ "
  echo " |  _ \\|  _| | |\\/| |  \\ \\/\\/ /| | | | | |  \\| | | | | | | |"
  echo " | |_) | |___| |  | |   \\_/\\_/ | | | |_| | |\\  | |_| | |_| |"
  echo " |____/|_____|_|  |_|            \\____\\___/|_| \\_|____/ \\___/ "
  echo "                BEM VINDO AO TELEGRAM 4.0"
  echo "=============================================================="
  echo -e "${reset}"
}

ask_default() {
  local prompt="$1"
  local def="$2"
  local out
  read -r -p "$prompt [$def]: " out
  if [ -z "$out" ]; then
    out="$def"
  fi
  printf "%s" "$out"
}

ask_yes_no() {
  local prompt="$1"
  local def="$2"
  local ans
  read -r -p "$prompt [$def]: " ans
  if [ -z "$ans" ]; then
    ans="$def"
  fi
  case "${ans,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    tr -d '\r' < "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
  STEP="${STEP:-}"
  STEP="${STEP//$'\r'/}"
  INSTALL_DIR="${INSTALL_DIR:-}"
  ZIP_URL="${ZIP_URL:-}"
  SERVICE_NAME="${SERVICE_NAME:-}"
  PORT="${PORT:-}"
  ADMIN_USER="${ADMIN_USER:-}"
}

write_state() {
  cat > "$STATE_FILE" <<EOF
STEP="$STEP"
INSTALL_DIR="$INSTALL_DIR"
ZIP_URL="$ZIP_URL"
SERVICE_NAME="$SERVICE_NAME"
PORT="$PORT"
ADMIN_USER="$ADMIN_USER"
EOF
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (sudo)."
    exit 1
  fi
}

get_app_dir() {
  if [ -f "$INSTALL_DIR/telegram_api_v4.py" ]; then
    echo "$INSTALL_DIR"
    return
  fi
  if [ -f "$INSTALL_DIR/telegram-saas/telegram_api_v4.py" ]; then
    echo "$INSTALL_DIR/telegram-saas"
    return
  fi
  echo "$INSTALL_DIR"
}

prompt_core() {
  INSTALL_DIR="$(ask_default "Final install path" "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}")"
  ZIP_URL="$(ask_default "Zip URL (raw)" "${ZIP_URL:-$DEFAULT_ZIP_URL}")"
  SERVICE_NAME="$(ask_default "Systemd service name" "${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}")"
  PORT="$(ask_default "Port" "${PORT:-$DEFAULT_PORT}")"
  ADMIN_USER="$(ask_default "Web admin user" "${ADMIN_USER:-admin}")"
  STEP="deps"
  write_state
}

install_deps() {
  echo "Installing OS dependencies..."
  apt-get update -y
  apt-get install -y python3 python3-venv python3-pip unzip curl poppler-utils
  STEP="download"
  write_state
}

maybe_prompt_github_token() {
  if [ -z "${GH_TOKEN:-}" ]; then
    read -r -s -p "GitHub token (leave blank if public): " GH_TOKEN
    echo ""
  fi
}

download_zip() {
  echo "Downloading zip..."
  local tmp_zip="/tmp/telegram-saas.zip"
  rm -f "$tmp_zip"
  if [[ "$ZIP_URL" == *"github"* ]]; then
    maybe_prompt_github_token
  fi
  if [ -n "${GH_TOKEN:-}" ]; then
    curl -fL -H "Authorization: token $GH_TOKEN" -o "$tmp_zip" "$ZIP_URL"
  else
    curl -fL -o "$tmp_zip" "$ZIP_URL"
  fi
  STEP="unzip"
  write_state
}

unzip_app() {
  echo "Unzipping to $INSTALL_DIR..."
  mkdir -p "$INSTALL_DIR"
  unzip -o /tmp/telegram-saas.zip -d "$INSTALL_DIR"
  if [ -d "$INSTALL_DIR/telegram-saas" ] && [ -f "$INSTALL_DIR/telegram-saas/telegram_api_v4.py" ]; then
    echo "Detected nested folder, flattening..."
    shopt -s dotglob
    mv "$INSTALL_DIR/telegram-saas/"* "$INSTALL_DIR/"
    shopt -u dotglob
    rmdir "$INSTALL_DIR/telegram-saas" || true
  fi
  STEP="venv"
  write_state
}

setup_venv() {
  echo "Setting up venv and installing requirements..."
  local app_dir
  app_dir="$(get_app_dir)"
  python3 -m venv "$INSTALL_DIR/venv"
  "$INSTALL_DIR/venv/bin/pip" install --upgrade pip
  "$INSTALL_DIR/venv/bin/pip" install -r "$app_dir/requirements.txt"
  STEP="config"
  write_state
}

configure_app() {
  ADMIN_USER="$(ask_default "Web admin user" "${ADMIN_USER:-admin}")"
  while true; do
    local pass1 pass2
    read -r -p "Web admin password (visible): " pass1
    read -r -p "Confirm password (visible): " pass2
    if [ "$pass1" != "$pass2" ]; then
      echo "Passwords do not match. Try again."
      continue
    fi
    echo "Confirm user: $ADMIN_USER"
    echo "Confirm pass: $pass1"
    if ask_yes_no "Proceed?" "y"; then
      ADMIN_PASS="$pass1"
      break
    fi
  done

  local app_dir
  app_dir="$(get_app_dir)"
  python3 - <<PY
import json
import os
import secrets

path = os.path.join("$app_dir", "config.json")
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        with open(path, "r", encoding="utf-8-sig") as f:
            cfg = json.load(f)
else:
    cfg = {}

cfg.setdefault("server", {})
cfg["server"]["port"] = int("$PORT")

cfg.setdefault("admin", {})
cfg["admin"]["user"] = "$ADMIN_USER"
cfg["admin"]["pass_plain"] = "$ADMIN_PASS"
if not cfg["admin"].get("session_secret"):
    cfg["admin"]["session_secret"] = secrets.token_urlsafe(48)

cfg.setdefault("api", {})
if not cfg["api"].get("bearer_token"):
    cfg["api"]["bearer_token"] = secrets.token_urlsafe(48)

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
PY

  STEP="redis"
  write_state
}

install_redis_inline() {
  local app_dir="$1"
  if [ -z "$app_dir" ]; then
    return
  fi

  if ! ask_yes_no "Install Redis queue (recommended)?" "y"; then
    STEP="service"
    write_state
    return
  fi

  echo "Installing Redis..."
  apt-get update -y
  apt-get install -y redis-server

  if [ ! -f "$app_dir/config.json" ]; then
    echo "config.json not found at $app_dir. Skipping Redis config."
    STEP="service"
    write_state
    return
  fi

  mapfile -t _redis_vals < <(python3 - <<PY
import json
path = "$app_dir/config.json"
cfg = json.load(open(path, "r", encoding="utf-8"))
r = cfg.get("redis", {}) or {}
print(str(r.get("enabled", False)).lower())
print(r.get("host", "127.0.0.1"))
print(r.get("port", 6379))
print(r.get("password", ""))
PY
)

  local redis_enabled="${_redis_vals[0]}"
  local redis_host="${_redis_vals[1]}"
  local redis_port="${_redis_vals[2]}"
  local redis_pass="${_redis_vals[3]}"

  if [ "$redis_enabled" != "true" ]; then
    echo "Redis disabled in config.json. Skipping Redis config."
    STEP="service"
    write_state
    return
  fi

  if [ -z "$redis_pass" ]; then
    redis_pass="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"
    python3 - <<PY
import json
path = "$app_dir/config.json"
cfg = json.load(open(path, "r", encoding="utf-8"))
cfg.setdefault("redis", {})
cfg["redis"]["password"] = "$redis_pass"
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
PY
    echo "Generated Redis password and saved to config.json."
  fi

  local conf="/etc/redis/redis.conf"
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

  STEP="service"
  write_state
}

install_redis() {
  local app_dir
  app_dir="$(get_app_dir)"
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local redis_installer="$script_dir/redis_install.sh"

  if ! ask_yes_no "Install Redis queue (recommended)?" "y"; then
    STEP="service"
    write_state
    return
  fi

  if [ -f "$redis_installer" ]; then
    bash "$redis_installer" "$app_dir"
    STEP="service"
    write_state
    return
  fi

  install_redis_inline "$app_dir"
}

create_service() {
  echo "Creating systemd service..."
  local app_dir
  app_dir="$(get_app_dir)"
  local svc_path="/etc/systemd/system/${SERVICE_NAME}.service"
  cat > "$svc_path" <<EOF
[Unit]
Description=Telegram SaaS
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$app_dir
ExecStart=$INSTALL_DIR/venv/bin/python $app_dir/telegram_api_v4.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  STEP="done"
  write_state
}

main() {
  require_root
  load_state
  print_banner

  if [ -f "$STATE_FILE" ]; then
    if ! ask_yes_no "Resume previous install?" "y"; then
      rm -f "$STATE_FILE"
      STEP=""
    fi
  fi

  if [ -z "${STEP:-}" ]; then
    prompt_core
  fi

  while true; do
    case "$STEP" in
      deps) install_deps ;;
      download) download_zip ;;
      unzip) unzip_app ;;
      venv) setup_venv ;;
      config) configure_app ;;
      redis) install_redis ;;
      service) create_service ;;
      done)
        echo "Install already completed."
        break
        ;;
      *)
        echo "Unknown step: $STEP"
        exit 1
        ;;
    esac

    if [ "$STEP" = "done" ]; then
      echo "Done. Service: $SERVICE_NAME"
      echo "Open: http://<server-ip>:$PORT/"
      break
    fi
  done
}

main "$@"
