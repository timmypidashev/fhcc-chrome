# FHCC Chromebook Kiosk

Locked-down Chromium kiosk for school Chromebooks running Arch Linux.

- StevenBlack blocklist (~82k domains) blocked
- Custom local launcher page (kiddle, typing, docs, drive, slides)
- Fullscreen kiosk on tty1, autologin, no escape to TTY
- Updated by `git pull && sudo ./deploy.sh` on each laptop

## Repo layout

```
fhcc-chrome/
├── README.md             this file
├── install.sh            first-time setup (per laptop, root)
├── deploy.sh             redeploy policy + web after `git pull` (root)
├── convert-hosts.py      rebuild school_policy.json on the Mac
├── school_policy.json    committed artifact — what laptops load
└── web/
    ├── index.html        launcher (5 tiles)
    ├── shared.css
    └── shared.js
```

## Allowed sites

- kiddle.co — search
- typing.com — typing practice
- docs.google.com / drive.google.com / sheets.google.com / slides.google.com — Google Workspace
- accounts.google.com + Google CDN domains — sign-in, fonts, static assets
- `file:///*` — local launcher pages

Everything else on the StevenBlack list is blocked. Other sites still load (the blocklist is opt-out, not opt-in).

---

## Part 1 — Set up ONE Chromebook

Boot the Chromebook into Arch with an admin sudo user (call it `admin` here).

### 1a. System prep

```bash
sudo pacman -Syu
sudo useradd -m -G video,audio,input student
```

### 1b. Clone repo

```bash
sudo pacman -S --needed git
sudo git clone https://github.com/<you>/fhcc-chrome.git /opt/fhcc-chrome
sudo chown -R admin:admin /opt/fhcc-chrome
cd /opt/fhcc-chrome
```

### 1c. Run install

```bash
sudo ./install.sh
```

Installs chromium + xorg + mesa + openssh, deploys the policy and web pages, sets up tty1 autologin, locks VT switching.

### 1d. Enable SSH (so you can update remotely)

```bash
sudo systemctl enable --now sshd
ip a   # note the IP
```

From the Mac:
```bash
ssh admin@<chromebook-ip>
```

### 1e. Reboot and test

```bash
sudo reboot
```

After reboot: tty1 autologins `student` → X starts → fullscreen Chromium loads `file:///usr/local/share/kiosk/index.html`.

**Verify:**
- Tiles render with green background
- Each tile opens its site
- `youtube.com` in the address bar → blocked
- `Ctrl+Alt+F2` → nothing (VT locked)

---

## Part 2 — Replicate to the rest of the fleet

Repeat Part 1 on each Chromebook. ~10 min apiece, mostly waiting on `pacman`.

To skip the per-laptop install, `dd`-clone the disk of a working one and set a unique hostname:
```bash
hostnamectl set-hostname fhcc-cb-02
```

---

## Part 3 — Updating after deployment

### On the Mac

```bash
cd ~/path/to/fhcc-chrome

# If the blocklist or convert-hosts.py changed:
python3 convert-hosts.py

git add .
git commit -m "tweak launcher"
git push
```

### On each Chromebook

```bash
ssh admin@<chromebook-ip> 'cd /opt/fhcc-chrome && sudo git pull && sudo ./deploy.sh && sudo reboot'
```

Whole fleet at once:
```bash
for ip in 192.168.1.{50,51,52,53}; do
  ssh admin@$ip 'cd /opt/fhcc-chrome && sudo git pull && sudo ./deploy.sh && sudo reboot' &
done; wait
```

---

## Tweaking what's blocked

### Stricter blocklist variant

Edit `HOSTS_URL` near the top of `convert-hosts.py`:

| Suffix | Adds |
|---|---|
| `master/hosts` | ads + malware (current default) |
| `master/alternates/fakenews/hosts` | + fakenews |
| `master/alternates/fakenews-gambling/hosts` | + gambling |
| `master/alternates/fakenews-gambling-porn/hosts` | + porn |
| `master/alternates/fakenews-gambling-porn-social/hosts` | + social (recommended for school) |

Then `python3 convert-hosts.py && git commit -am 'switch blocklist' && git push`.

### Add an allowed site

Edit `ALLOWLIST` in `convert-hosts.py`, rebuild, commit.

### Add a tile to the launcher

Edit `web/index.html`, add another `<a class="tile">` block, commit.

---

## Admin escape hatches

VT switching is locked. If SSH also fails:

1. **Single-user mode** — append `single` to the kernel cmdline at the bootloader. Drops to root shell.
2. **Live USB** — mount the disk, remove `/etc/systemd/system/getty@tty1.service.d/override.conf`.

---

## Notes

- `URLAllowlist` overrides `URLBlocklist` per Chromium policy spec.
- Launcher uses `--incognito` so sessions don't persist. Kids re-sign-in to Google each session.
- `chromium` (official Arch) and `ungoogled-chromium` (AUR) both read `/etc/chromium/policies/managed/`. Swap freely — no other config changes needed.
- `school_policy.json` is committed (~2 MB) so Chromebooks don't need Python or GitHub raw access.
