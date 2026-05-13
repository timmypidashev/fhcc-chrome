#!/usr/bin/env bash
# Dead-simple kiosk setup. Creates a passwordless user, installs cage
# and all its runtime deps, wires a single systemd service that owns
# tty1 and runs chromium fullscreen. Run as root. Idempotent.
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

echo ">> Installing packages (cage + runtime deps + fonts)"
pacman -S --needed --noconfirm \
  chromium \
  cage \
  seatd \
  xorg-xwayland \
  mesa \
  libinput \
  xkeyboard-config \
  libxkbcommon \
  dbus \
  polkit \
  ttf-dejavu \
  noto-fonts

echo ">> Ensuring user '$KIOSK_USER' exists with no password"
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$KIOSK_USER"
fi
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

echo ">> Enabling required services (dbus, seatd)"
systemctl unmask seatd.service 2>/dev/null || true
systemctl enable --now seatd.service
# dbus is socket-activated and linked; just make sure it's running
systemctl start dbus.service 2>/dev/null || true

echo ">> Verifying cage binary"
test -x /usr/bin/cage || { echo "cage missing after install"; exit 3; }

echo ">> Writing $KIOSK_SERVICE"
cat >"$KIOSK_SERVICE" <<EOF
[Unit]
Description=FHCC Kiosk
After=systemd-user-sessions.service plymouth-quit-wait.service seatd.service dbus.service
Wants=seatd.service dbus.service
Conflicts=getty@tty1.service

[Service]
User=$KIOSK_USER
PAMName=login
WorkingDirectory=/home/$KIOSK_USER
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty
StandardOutput=journal
StandardError=journal
UtmpIdentifier=tty1
UtmpMode=user
Environment=XKB_DEFAULT_LAYOUT=us
ExecStart=/usr/bin/cage -s -- /usr/local/bin/school-kiosk
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
echo "default target  : $(systemctl get-default)"
echo "kiosk.service   : $(systemctl is-enabled kiosk.service)"
echo "seatd active    : $(systemctl is-active seatd)"
echo "dbus active     : $(systemctl is-active dbus)"
echo "$KIOSK_USER groups : $(id -nG "$KIOSK_USER")"
echo "$KIOSK_USER pw     : $(passwd -S "$KIOSK_USER" 2>/dev/null | awk '{print $2}') (NP = no password)"
echo "cage binary     : $(command -v cage)"
echo "chromium binary : $(command -v chromium)"
echo "launcher        : $(test -x /usr/local/bin/school-kiosk && echo OK || echo MISSING)"
echo
echo "Reboot to launch the kiosk: sudo reboot"
echo "Admin shell:                Ctrl+Alt+F2 (external kbd)"
echo
echo "If stuck at 'Reached target Multi-User System' after reboot:"
echo "  Switch to tty2 (Ctrl+Alt+F2), log in as admin, then:"
echo "    sudo journalctl -u kiosk.service -b --no-pager | head -80"
echo
echo "Disable kiosk: sudo systemctl disable --now kiosk.service \\"
echo "               && sudo systemctl set-default graphical.target \\"
echo "               && sudo systemctl enable sddm && sudo reboot"
