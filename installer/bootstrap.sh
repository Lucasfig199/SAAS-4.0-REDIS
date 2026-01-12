#!/usr/bin/env bash
set -euo pipefail

REPO="Lucasfig199/SAAS-4.0-REDIS"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/installer/install.sh"
API_URL="https://api.github.com/repos/${REPO}/contents/installer/install.sh?ref=${BRANCH}"

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  read -r -s -p "GitHub token (leave blank if public): " TOKEN
  echo ""
fi

fetch_install() {
  local out="install.sh"
  if [ -n "$TOKEN" ]; then
    if ! curl -fsSL -H "Authorization: token $TOKEN" "${RAW_URL}?v=$(date +%s)" -o "$out"; then
      curl -fsSL -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.raw" "$API_URL" -o "$out"
    fi
    export GH_TOKEN="$TOKEN"
  else
    curl -fsSL "${RAW_URL}?v=$(date +%s)" -o "$out"
  fi
}

fetch_install

awk 'NR==1{sub(/^\xef\xbb\xbf/,"")} {print}' install.sh | tr -d '\r' > install.sh.tmp
mv install.sh.tmp install.sh
chmod +x install.sh

if [ "$(id -u)" -eq 0 ]; then
  exec ./install.sh
else
  exec sudo ./install.sh
fi
