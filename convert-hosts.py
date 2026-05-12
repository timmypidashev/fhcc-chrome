#!/usr/bin/env python3
"""
Convert StevenBlack hosts blocklist into an ungoogled-chromium
URLBlocklist policy with an educational-site allowlist.

Output: ./school_policy.json
"""

import ipaddress
import json
import os
import sys
import urllib.request

HOSTS_URLS = [
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts",
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling/hosts",
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts",
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts",
]
OUTPUT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "school_policy.json")

ALLOWLIST = [
    "file:///*",
    "kiddle.co",
    "*.kiddle.co",
    "kiddle.com",
    "*.kiddle.com",
    "typing.com",
    "*.typing.com",
    "docs.google.com",
    "drive.google.com",
    "sheets.google.com",
    "slides.google.com",
    "accounts.google.com",
    "ssl.gstatic.com",
    "fonts.gstatic.com",
    "fonts.googleapis.com",
    "apis.google.com",
    "clients6.google.com",
    "lh3.googleusercontent.com",
]

SKIP_DOMAINS = {"localhost", "localhost.localdomain", "broadcasthost", "local"}


def fetch_hosts(url: str) -> str:
    print(f"Fetching {url} ...")
    with urllib.request.urlopen(url, timeout=60) as resp:
        return resp.read().decode("utf-8", errors="ignore")


def parse_hosts(text: str) -> list[str]:
    blocked = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        ip, domain = parts[0], parts[1].lower()
        if ip not in ("0.0.0.0", "127.0.0.1"):
            continue
        if domain in SKIP_DOMAINS:
            continue
        if "." not in domain:
            continue
        try:
            ipaddress.ip_address(domain)
            continue
        except ValueError:
            pass
        blocked.add(domain)
    return sorted(blocked)


def build_policy(blocked: list[str]) -> dict:
    return {
        "HomepageLocation": "file:///usr/local/share/kiosk/index.html",
        "HomepageIsNewTabPage": False,
        "RestoreOnStartup": 4,
        "RestoreOnStartupURLs": ["file:///usr/local/share/kiosk/index.html"],
        "URLAllowlist": ALLOWLIST,
        "URLBlocklist": blocked,
        "BookmarkBarEnabled": True,
        "ManagedBookmarks": [
            {"name": "Kiddle", "url": "https://kiddle.co"},
            {"name": "Typing.com", "url": "https://typing.com"},
            {"name": "Nitrotype", "url": "https://nitrotype.com"},
            {"name": "Google Docs", "url": "https://docs.google.com"},
        ],
        "IncognitoModeAvailability": 1,
        "DeveloperToolsAvailability": 2,
        "BrowserSignin": 0,
        "SyncDisabled": True,
        "PasswordManagerEnabled": False,
        "AutofillAddressEnabled": False,
        "AutofillCreditCardEnabled": False,
        "DefaultDownloadDirectory": "${user_home}/Downloads",
        "DownloadRestrictions": 3,
        "SafeBrowsingEnabled": True,
        "PrintingEnabled": False,
        "TranslateEnabled": False,
        "SpellcheckEnabled": True,
        "ShowFullUrlsInAddressBar": True,
    }


def main() -> int:
    merged = set()
    for url in HOSTS_URLS:
        text = fetch_hosts(url)
        merged.update(parse_hosts(text))
    blocked = sorted(merged)
    print(f"Merged {len(blocked)} unique domains across {len(HOSTS_URLS)} lists")
    policy = build_policy(blocked)
    with open(OUTPUT_FILE, "w") as f:
        json.dump(policy, f, indent=2)
    print(f"Wrote {OUTPUT_FILE}")
    print(f"Allowlist entries: {len(ALLOWLIST)}")
    print(f"Blocklist entries: {len(blocked)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
