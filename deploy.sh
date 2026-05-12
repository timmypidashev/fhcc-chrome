#!/usr/bin/env bash
# Deploys the kiosk policy, local web pages, and launcher script.
# Run as root after `git pull`. Pure file copy — does not touch packages,
# users, autologin, xorg, or systemd.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_SRC="$REPO_DIR/school_policy.json"
POLICY_DIR="/etc/chromium/policies/managed"
POLICY_FILE="$POLICY_DIR/school_policy.json"
WEB_SRC="$REPO_DIR/web"
WEB_DIR="/usr/local/share/kiosk"
LAUNCH_SCRIPT="/usr/local/bin/school-kiosk"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

echo ">> Policy → $POLICY_FILE"
mkdir -p "$POLICY_DIR"
install -m 0644 "$POLICY_SRC" "$POLICY_FILE"

echo ">> Web pages → $WEB_DIR"
mkdir -p "$WEB_DIR"
install -m 0644 "$WEB_SRC"/*.html "$WEB_DIR/"
install -m 0644 "$WEB_SRC"/*.css  "$WEB_DIR/" 2>/dev/null || true
install -m 0644 "$WEB_SRC"/*.js   "$WEB_DIR/" 2>/dev/null || true

echo ">> Launcher → $LAUNCH_SCRIPT"
cat >"$LAUNCH_SCRIPT" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/chromium \
  --kiosk \
  --no-first-run \
  --no-default-browser-check \
  --disable-extensions \
  --disable-plugins \
  --disable-sync \
  --disable-default-apps \
  --disable-translate \
  --disable-background-networking \
  --disable-component-extensions-with-background-pages \
  --disable-device-discovery-notifications \
  --disable-hang-monitor \
  --disable-popup-blocking \
  --disable-prompt-on-repost \
  --disable-component-update \
  --disable-features=TranslateUI \
  --check-for-update-interval=31536000 \
  --overscroll-history-navigation=0 \
  --noerrdialogs \
  --incognito \
  "file:///usr/local/share/kiosk/index.html"
EOF
chmod 0755 "$LAUNCH_SCRIPT"

echo "Done. Run \`school-kiosk\` to launch (or add it to your dwm autostart)."
