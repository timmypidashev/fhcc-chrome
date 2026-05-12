#!/usr/bin/env bash
# Dead-simple kiosk setup. Creates a passwordless user, installs cage,
# wires a single systemd service that owns tty1 and runs chromium as
# the entire screen. Run as root. Idempotent — safe to re-run any time.
set -euo pipefail

KIOSK_USER="${KIOSK_USER:-student}"
KIOSK_SERVICE="/etc/systemd/system/kiosk.service"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

if [[ ! -x /usr/local/bin/school-kiosk ]]; then
  echo "Launcher missing. Run sudo ./deploy.sh first."
  exit 2
fi

echo ">> Installing packages"
pacman -S --needed --noconfirm chromium cage seatd xorg-xwayland

echo ">> Ensuring user '$KIOSK_USER' exists with no password"
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$KIOSK_USER"
fi
# wipe password so nothing can ever prompt for one
passwd -d "$KIOSK_USER" >/dev/null

echo ">> Adding $KIOSK_USER to required groups (video, audio, input, seat)"
groupadd -f seat
usermod -aG video,audio,input,seat "$KIOSK_USER"

echo ">> Cleaning up any prior attempts"
systemctl disable --now sddm 2>/dev/null || true
systemctl disable --now getty@tty1.service 2>/dev/null || true
rm -rf /etc/systemd/system/getty@tty1.service.d
rm -f /etc/sddm.conf.d/00-school-kiosk.conf
rm -f /usr/share/xsessions/school-kiosk.desktop
rm -f /etc/X11/Xwrapper.config

echo ">> Default target → multi-user.target"
systemctl set-default multi-user.target

echo ">> Enabling seatd"
systemctl enable --now seatd

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
echo "=== Sanity ==="
echo "default target : $(systemctl get-default)"
echo "kiosk.service  : $(systemctl is-enabled kiosk.service)"
echo "seatd          : $(systemctl is-active seatd)"
echo "$KIOSK_USER groups: $(id -nG "$KIOSK_USER")"
echo "$KIOSK_USER pw    : $(passwd -S "$KIOSK_USER" 2>/dev/null | awk '{print $2}') (NP = no password)"
echo
echo "Reboot to launch the kiosk: sudo reboot"
echo "Admin shell:                 Ctrl+Alt+F2 (external kbd) or Search+Ctrl+Alt+2"
echo "Debug on failure:            sudo journalctl -u kiosk.service -b --no-pager"
echo "Undo everything:"
echo "  sudo systemctl disable --now kiosk.service"
echo "  sudo systemctl set-default graphical.target"
echo "  sudo systemctl enable sddm"
echo "  sudo reboot"
