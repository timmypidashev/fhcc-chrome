#!/usr/bin/env bash
# Dead-simple kiosk setup. Creates a passwordless user, installs cage
# and its runtime deps, wires a single systemd service that owns tty1
# and runs chromium fullscreen. Uses systemd-logind for seat management
# (no seatd). Run as root. Idempotent.
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
pacman -S --needed --noconfirm \
  chromium \
  cage \
  xorg-xwayland \
  mesa \
  libinput \
  xkeyboard-config \
  libxkbcommon \
  dbus \
  polkit \
  ttf-dejavu \
  noto-fonts

echo ">> Checking AUR helper"
if [[ -z "${SUDO_USER:-}" ]] || [[ "$SUDO_USER" == "root" ]]; then
  echo "ERROR: AUR install needs a non-root user. Run via 'sudo' from your admin account."
  exit 4
fi

# Rebuild yay if it's missing or broken (typical libalpm.so.N error after a long
# gap between system upgrades). yay-bin tracks library bumps; yay-source does not.
if ! sudo -u "$SUDO_USER" yay --version >/dev/null 2>&1; then
  echo ">> yay is missing or broken — reinstalling yay-bin"
  pacman -R --noconfirm yay 2>/dev/null || true
  rm -rf /tmp/yay-bin
  sudo -u "$SUDO_USER" git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
  pushd /tmp/yay-bin >/dev/null
  sudo -u "$SUDO_USER" makepkg -si --noconfirm
  popd >/dev/null
  rm -rf /tmp/yay-bin
fi

echo ">> Installing swhkd from AUR"
if ! command -v swhkd >/dev/null; then
  sudo -u "$SUDO_USER" yay -S --noconfirm swhkd-git
fi

echo ">> Ensuring user '$KIOSK_USER' exists with no password"
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$KIOSK_USER"
fi
passwd -d "$KIOSK_USER" >/dev/null

echo ">> Adding $KIOSK_USER to required groups (video, audio, input)"
usermod -aG video,audio,input "$KIOSK_USER"

echo ">> Cleaning up any prior attempts"
systemctl disable --now sddm 2>/dev/null || true
systemctl disable --now getty@tty1.service 2>/dev/null || true
systemctl disable --now seatd.service 2>/dev/null || true
rm -rf /etc/systemd/system/getty@tty1.service.d
rm -f /etc/sddm.conf.d/00-school-kiosk.conf
rm -f /usr/share/xsessions/school-kiosk.desktop
rm -f /etc/X11/Xwrapper.config

echo ">> Default target → multi-user.target"
systemctl set-default multi-user.target

echo ">> Ensuring dbus is running"
systemctl is-active dbus.service >/dev/null || systemctl start dbus.service

echo ">> Writing swhkd config (blocks Ctrl+T, Ctrl+N, Ctrl+Shift+T, F11)"
mkdir -p /etc/swhkd
cat >/etc/swhkd/swhkdrc <<'EOF'
ctrl + t
  true

ctrl + n
  true

ctrl + shift + t
  true

f11
  true
EOF
chmod 0644 /etc/swhkd/swhkdrc

echo ">> Writing swhkd.service"
cat >/etc/systemd/system/swhkd.service <<'EOF'
[Unit]
Description=Simple Wayland HotKey Daemon (blocks kiosk-escape keys)
After=multi-user.target
Before=kiosk.service

[Service]
Type=simple
ExecStart=/usr/bin/swhkd -c /etc/swhkd/swhkdrc
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo ">> Enabling swhkd.service"
systemctl enable swhkd.service

echo ">> Writing $KIOSK_SERVICE"
cat >"$KIOSK_SERVICE" <<EOF
[Unit]
Description=FHCC Kiosk
After=systemd-user-sessions.service plymouth-quit-wait.service dbus.service
Wants=dbus.service
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
echo "dbus active     : $(systemctl is-active dbus)"
echo "logind active   : $(systemctl is-active systemd-logind)"
echo "$KIOSK_USER groups : $(id -nG "$KIOSK_USER")"
echo "$KIOSK_USER pw     : $(passwd -S "$KIOSK_USER" 2>/dev/null | awk '{print $2}') (NP = no password)"
echo "cage binary     : $(command -v cage)"
echo "chromium binary : $(command -v chromium)"
echo "swhkd binary    : $(command -v swhkd)"
echo "swhkd.service   : $(systemctl is-enabled swhkd.service)"
echo "launcher        : $(test -x /usr/local/bin/school-kiosk && echo OK || echo MISSING)"
echo
echo "Reboot to launch the kiosk: sudo reboot"
echo "Admin shell:                Ctrl+Alt+F2 (external kbd)"
echo
echo "If stuck after reboot:"
echo "  Ctrl+Alt+F2 → admin → sudo journalctl -u kiosk.service -b --no-pager | head -80"
echo
echo "Disable kiosk: sudo systemctl disable --now kiosk.service \\"
echo "               && sudo systemctl set-default graphical.target \\"
echo "               && sudo systemctl enable sddm && sudo reboot"
