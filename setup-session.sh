#!/usr/bin/env bash
# One-time setup: makes the chromebook boot straight into the kiosk.
# No display manager, no shell login, no startx — a single systemd service
# owns tty1 and runs X with the kiosk as the only X client.
# Run as root from the admin account. Idempotent.
set -euo pipefail

KIOSK_USER="${KIOSK_USER:-student}"
KIOSK_SERVICE="/etc/systemd/system/kiosk.service"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  echo "User '$KIOSK_USER' does not exist."
  exit 2
fi
if [[ ! -x /usr/local/bin/school-kiosk ]]; then
  echo "Run sudo ./deploy.sh first (missing /usr/local/bin/school-kiosk)."
  exit 3
fi

KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"

echo ">> Installing packages"
pacman -S --needed --noconfirm chromium openbox xorg-server xorg-xinit

echo ">> Disabling SDDM and graphical.target"
systemctl disable --now sddm 2>/dev/null || true
systemctl set-default multi-user.target

echo ">> Cleaning up any old getty autologin override"
rm -rf /etc/systemd/system/getty@tty1.service.d
rm -f /etc/sddm.conf.d/00-school-kiosk.conf
rm -f /usr/share/xsessions/school-kiosk.desktop

echo ">> Disabling getty@tty1 (kiosk owns tty1)"
systemctl disable --now getty@tty1.service 2>/dev/null || true

echo ">> Allowing non-root X start"
mkdir -p /etc/X11
cat >/etc/X11/Xwrapper.config <<'EOF'
allowed_users=anybody
needs_root_rights=yes
EOF

echo ">> Writing $KIOSK_SERVICE"
cat >"$KIOSK_SERVICE" <<EOF
[Unit]
Description=FHCC kiosk
After=systemd-user-sessions.service plymouth-quit-wait.service
Conflicts=getty@tty1.service
After=getty@tty1.service

[Service]
User=$KIOSK_USER
PAMName=login
WorkingDirectory=$KIOSK_HOME
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty
StandardOutput=journal
StandardError=journal
UtmpIdentifier=tty1
UtmpMode=user
ExecStart=/usr/bin/startx /usr/local/bin/school-kiosk -- vt1 -keeptty -novtswitch -nolisten tcp
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo ">> Enabling kiosk.service"
systemctl daemon-reload
systemctl enable kiosk.service

echo
echo "=== Sanity check ==="
echo "default target: $(systemctl get-default)"
echo "kiosk.service: $(systemctl is-enabled kiosk.service)"
echo "sddm: $(systemctl is-enabled sddm 2>/dev/null || echo disabled)"
echo "getty@tty1: $(systemctl is-enabled getty@tty1 2>/dev/null || echo disabled)"
echo
echo "Reboot to enter the kiosk:  sudo reboot"
echo "Admin: switch to tty2 with Ctrl+Alt+F2 (external kbd) or Search+Ctrl+Alt+2."
echo "Disable kiosk: sudo systemctl disable --now kiosk.service && sudo systemctl set-default graphical.target"
