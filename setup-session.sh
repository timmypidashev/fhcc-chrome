#!/usr/bin/env bash
# One-time setup: makes the chromebook boot straight into the kiosk.
# Uses cage (Wayland kiosk compositor) as a systemd service. No display
# manager, no shell, no X.
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

echo ">> Installing packages"
pacman -S --needed --noconfirm chromium cage seatd xorg-xwayland

echo ">> Cleaning up any prior attempts"
systemctl disable --now sddm 2>/dev/null || true
systemctl disable --now getty@tty1.service 2>/dev/null || true
rm -rf /etc/systemd/system/getty@tty1.service.d
rm -f /etc/sddm.conf.d/00-school-kiosk.conf
rm -f /usr/share/xsessions/school-kiosk.desktop
rm -f /etc/X11/Xwrapper.config

echo ">> Default target → multi-user.target (no graphical login)"
systemctl set-default multi-user.target

echo ">> Enabling seatd (cage needs seat management)"
systemctl enable --now seatd
gpasswd -a "$KIOSK_USER" seat

echo ">> Writing $KIOSK_SERVICE"
cat >"$KIOSK_SERVICE" <<EOF
[Unit]
Description=FHCC Kiosk
After=systemd-user-sessions.service plymouth-quit-wait.service seatd.service
Wants=seatd.service
Conflicts=getty@tty1.service

[Service]
User=$KIOSK_USER
PAMName=login
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty
StandardOutput=journal
StandardError=journal
UtmpIdentifier=tty1
UtmpMode=user
Environment=XDG_SESSION_TYPE=wayland
ExecStart=/usr/bin/cage -- /usr/local/bin/school-kiosk
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
echo "default target : $(systemctl get-default)"
echo "kiosk.service  : $(systemctl is-enabled kiosk.service)"
echo "seatd          : $(systemctl is-enabled seatd)"
echo "sddm           : $(systemctl is-enabled sddm 2>/dev/null || echo disabled)"
echo "getty@tty1     : $(systemctl is-enabled getty@tty1 2>/dev/null || echo disabled)"
echo "$KIOSK_USER in seat group : $(id -nG "$KIOSK_USER" | grep -o seat || echo NO)"
echo
echo "Reboot to enter the kiosk: sudo reboot"
echo "Admin shell:               Ctrl+Alt+F2 (external kbd) or Search+Ctrl+Alt+2"
echo "Debug failed boot:         sudo journalctl -u kiosk.service -b --no-pager"
echo "Disable kiosk:             sudo systemctl disable --now kiosk.service && sudo systemctl set-default graphical.target && sudo systemctl enable sddm && sudo reboot"
