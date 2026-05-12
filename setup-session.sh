#!/usr/bin/env bash
# One-time setup: installs the SDDM X session for the kiosk and configures
# autologin for the student user. Run as root from the admin account.
# Idempotent — safe to re-run.
set -euo pipefail

KIOSK_USER="${KIOSK_USER:-student}"
SESSION_FILE="/usr/share/xsessions/school-kiosk.desktop"
SDDM_CONF="/etc/sddm.conf.d/00-school-kiosk.conf"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  echo "User '$KIOSK_USER' does not exist. Create it first:"
  echo "  sudo useradd -m -G video,audio,input $KIOSK_USER"
  exit 2
fi

if [[ ! -x /usr/local/bin/school-kiosk ]]; then
  echo "Launcher missing: /usr/local/bin/school-kiosk"
  echo "Run sudo ./deploy.sh first."
  exit 3
fi

echo ">> Installing required packages"
pacman -S --needed --noconfirm chromium matchbox-window-manager

echo ">> X session → $SESSION_FILE"
cat >"$SESSION_FILE" <<EOF
[Desktop Entry]
Name=School Kiosk
Comment=Locked-down Chromium kiosk
Exec=/usr/local/bin/school-kiosk
Type=Application
DesktopNames=school-kiosk
EOF
chmod 0644 "$SESSION_FILE"

echo ">> SDDM autologin → $SDDM_CONF ($KIOSK_USER → school-kiosk)"
mkdir -p /etc/sddm.conf.d
cat >"$SDDM_CONF" <<EOF
[Autologin]
User=$KIOSK_USER
Session=school-kiosk.desktop
EOF
chmod 0644 "$SDDM_CONF"

echo
echo "Done."
echo "  - Reboot to enter the kiosk as $KIOSK_USER."
echo "  - Admin shell: Ctrl+Alt+F2 → tty2 → log in as your admin user."
echo "  - Disable kiosk temporarily: sudo rm $SDDM_CONF && sudo systemctl restart sddm"
