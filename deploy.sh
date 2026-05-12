#!/usr/bin/env bash
# Redeploy policy on a laptop after `git pull`. Does not touch packages or autologin.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_SRC="$REPO_DIR/school_policy.json"
POLICY_FILE="/etc/chromium/policies/managed/school_policy.json"
WEB_SRC="$REPO_DIR/web"
WEB_DIR="/usr/local/share/kiosk"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

install -m 0644 "$POLICY_SRC" "$POLICY_FILE"

mkdir -p "$WEB_DIR"
install -m 0644 "$WEB_SRC"/*.html "$WEB_DIR/"
install -m 0644 "$WEB_SRC"/*.css "$WEB_DIR/" 2>/dev/null || true
install -m 0644 "$WEB_SRC"/*.js  "$WEB_DIR/" 2>/dev/null || true

echo "Deployed policy + web pages. Restart Chromium to apply."
