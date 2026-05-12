# FHCC Chromebook Kiosk

Chromium policy + local launcher page for school Chromebooks running Arch + dwm.

Blocks ~170k domains (StevenBlack base + fakenews + gambling + porn + social). Serves a green tile launcher with Kiddle, Typing.com, Google Docs / Drive / Slides.

## Contents

| Path | Purpose |
|---|---|
| `deploy.sh` | Copies policy + web pages + launcher into place (root) |
| `convert-hosts.py` | Rebuilds `school_policy.json` on the Mac |
| `school_policy.json` | Committed artifact — what each Chromebook loads |
| `web/index.html` | Launcher with tiles |
| `web/shared.{css,js}` | Styles + clock |

## What deploy.sh does

Three plain file copies, run as root:

| Source | Destination |
|---|---|
| `school_policy.json` | `/etc/chromium/policies/managed/school_policy.json` |
| `web/*.{html,css,js}` | `/usr/local/share/kiosk/` |
| inline launcher script | `/usr/local/bin/school-kiosk` |

It does **not** install packages, create users, configure autologin, write `.xinitrc`, or touch systemd. Chromebook setup (Xorg, dwm, user) is assumed already done.

## Per-Chromebook setup

```bash
sudo git clone https://github.com/<you>/fhcc-chrome.git /opt/fhcc-chrome
cd /opt/fhcc-chrome
sudo ./deploy.sh
```

Then make sure `chromium` is installed:
```bash
sudo pacman -S --needed chromium
```

Launch the kiosk:
```bash
school-kiosk
```

Or wire it into dwm autostart so it opens with the session (depends on how your dwm setup runs autostart — common patterns: a line in `~/.xinitrc` before `exec dwm`, an entry in an `autostart.sh` your dwm patch calls, or a keybind in `config.h`).

## Updating

On the Mac:
```bash
python3 convert-hosts.py     # only if blocklist or allowlist changed
git add . && git commit -m "..." && git push
```

On the Chromebook:
```bash
cd /opt/fhcc-chrome
sudo git pull
sudo ./deploy.sh
# restart chromium to reload the policy
```
