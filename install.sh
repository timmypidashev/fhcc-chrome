#!/usr/bin/env bash
# One-shot installer for FHCC kiosk Chromebook.
# Pre-built school_policy.json must be in repo (built on Mac via convert-hosts.py).
# Run as root: sudo ./install.sh
set -euo pipefail

KIOSK_USER="${KIOSK_USER:-student}"
KIOSK_URL="${KIOSK_URL:-file:///usr/local/share/kiosk/index.html}"
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

if [[ ! -f "$POLICY_SRC" ]]; then
  echo "Missing $POLICY_SRC. Build it on the Mac first: python3 convert-hosts.py"
  exit 1
fi

echo ">> Installing packages"
pacman -Sy --noconfirm --needed chromium xorg-server xorg-xinit mesa unclutter openssh git

echo ">> Deploying policy to $POLICY_FILE"
mkdir -p "$POLICY_DIR"
install -m 0644 "$POLICY_SRC" "$POLICY_FILE"

echo ">> Deploying local web pages to $WEB_DIR"
mkdir -p "$WEB_DIR"
install -m 0644 "$WEB_SRC"/*.html "$WEB_DIR/"
install -m 0644 "$WEB_SRC"/*.css "$WEB_DIR/" 2>/dev/null || true
install -m 0644 "$WEB_SRC"/*.js "$WEB_DIR/" 2>/dev/null || true

echo ">> Installing launch script at $LAUNCH_SCRIPT"
cat >"$LAUNCH_SCRIPT" <<EOF
#!/usr/bin/env bash
xset s off -dpms s noblank 2>/dev/null || true
unclutter -idle 1 -root &>/dev/null &
exec /usr/bin/chromium \\
  --kiosk \\
  --no-first-run \\
  --no-default-browser-check \\
  --disable-extensions \\
  --disable-plugins \\
  --disable-sync \\
  --disable-default-apps \\
  --disable-translate \\
  --disable-background-networking \\
  --disable-component-extensions-with-background-pages \\
  --disable-device-discovery-notifications \\
  --disable-hang-monitor \\
  --disable-popup-blocking \\
  --disable-prompt-on-repost \\
  --disable-component-update \\
  --disable-features=TranslateUI \\
  --check-for-update-interval=31536000 \\
  --overscroll-history-navigation=0 \\
  --noerrdialogs \\
  --incognito \\
  "$KIOSK_URL"
EOF
chmod +x "$LAUNCH_SCRIPT"

echo ">> Configuring tty1 auto-login for user $KIOSK_USER"
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat >/etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"
if [[ -z "$KIOSK_HOME" ]]; then
  echo "User $KIOSK_USER not found. Create it then re-run." >&2
  exit 2
fi

echo ">> Writing $KIOSK_HOME/.bash_profile (auto-startx on tty1)"
cat >"$KIOSK_HOME/.bash_profile" <<'EOF'
if [[ -z "$DISPLAY" && "$XDG_VTNR" == "1" ]]; then
  exec startx
fi
EOF
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.bash_profile"

echo ">> Writing $KIOSK_HOME/.xinitrc"
cat >"$KIOSK_HOME/.xinitrc" <<'EOF'
exec /usr/local/bin/school-kiosk
EOF
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.xinitrc"

echo ">> Locking VT switching"
mkdir -p /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/kiosk.conf <<EOF
[Login]
NAutoVTs=1
ReserveVT=0
EOF

systemctl daemon-reload

echo
echo "Done. Reboot to enter kiosk."
echo "To update blocklist later: pull repo, re-run sudo ./install.sh (or just deploy.sh)."
