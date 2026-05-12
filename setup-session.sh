#!/usr/bin/env bash
# One-time setup: disables SDDM, configures getty@tty1 to autologin the
# student user, and wires student's startup files to launch the kiosk.
# Run as root from the admin account. Idempotent — safe to re-run.
set -euo pipefail

KIOSK_USER="${KIOSK_USER:-student}"
GETTY_OVERRIDE="/etc/systemd/system/getty@tty1.service.d/override.conf"

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

KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"

echo ">> Installing required packages"
pacman -S --needed --noconfirm chromium openbox xorg-server xorg-xinit

echo ">> Disabling SDDM (if present)"
systemctl disable --now sddm 2>/dev/null || true
rm -f /etc/sddm.conf.d/00-school-kiosk.conf
rm -f /usr/share/xsessions/school-kiosk.desktop

echo ">> Autologin on tty1 → $KIOSK_USER"
mkdir -p "$(dirname "$GETTY_OVERRIDE")"
cat >"$GETTY_OVERRIDE" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

echo ">> Writing $KIOSK_HOME/.bash_profile (auto-startx on tty1)"
cat >"$KIOSK_HOME/.bash_profile" <<'EOF'
if [[ -z "$DISPLAY" && "$XDG_VTNR" == "1" ]]; then
  exec startx -- -nolisten tcp vt1 &>/dev/null
fi
EOF
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.bash_profile"

echo ">> Writing $KIOSK_HOME/.xinitrc (launches the kiosk)"
cat >"$KIOSK_HOME/.xinitrc" <<'EOF'
exec /usr/local/bin/school-kiosk
EOF
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.xinitrc"

systemctl daemon-reload

echo
echo "Done."
echo "  - Reboot to enter the kiosk as $KIOSK_USER."
echo "  - Admin shell: Ctrl+Alt+F2 on external keyboard, or"
echo "    Ctrl+Alt+Search+2 on the chromebook keyboard."
echo "  - Disable kiosk: sudo rm $GETTY_OVERRIDE && sudo systemctl daemon-reload"
