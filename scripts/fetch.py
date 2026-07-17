#!/usr/bin/env python3
"""
Собирает IPv4/IPv6-префиксы популярных сервисов для proxy/VPN split-tunnel.

Источники двух типов:
  1. Официальные фиды провайдера (самые точные, где есть).
  2. Announced prefixes по ASN через публичный RIPEstat API (без ключа).

Часть сервисов (см. SHARED_INFRA_NOTES) сидит на общих CDN/облаках —
для них точный список по IP принципиально неполный или пересекается
с чужими доменами на той же инфраструктуре. Такие сервисы либо не
включены, либо помечены в README отдельно.
"""
from __future__ import annotations

import ipaddress
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
MIKROTIK_DIR = ROOT / "mikrotik"
ADDRESS_LIST_NAME = "wg2-nets"

USER_AGENT = "network-prefixes-fetcher/1.0 (+https://github.com/evgen66rus/network-prefixes)"


def http_get(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def ripestat_prefixes(asn: int) -> list[str]:
    url = f"https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS{asn}"
    data = json.loads(http_get(url))
    return [p["prefix"] for p in data["data"]["prefixes"]]


def dedupe_and_sort(prefixes: list[str]) -> list[str]:
    nets = set()
    for p in prefixes:
        try:
            nets.add(ipaddress.ip_network(p, strict=False))
        except ValueError:
            continue
    return [str(n) for n in sorted(nets, key=lambda n: (n.version, n))]


# --- Официальные фиды -------------------------------------------------

def fetch_telegram() -> list[str]:
    text = http_get("https://core.telegram.org/resources/cidr.txt").decode()
    return [line.strip() for line in text.splitlines() if line.strip()]


def fetch_cloudflare() -> list[str]:
    v4 = http_get("https://www.cloudflare.com/ips-v4/").decode().splitlines()
    v6 = http_get("https://www.cloudflare.com/ips-v6/").decode().splitlines()
    return [l.strip() for l in v4 + v6 if l.strip()]


def fetch_amazon() -> list[str]:
    data = json.loads(http_get("https://ip-ranges.amazonaws.com/ip-ranges.json"))
    v4 = [p["ip_prefix"] for p in data["prefixes"]]
    v6 = [p["ipv6_prefix"] for p in data["ipv6_prefixes"]]
    return v4 + v6


def fetch_microsoft() -> list[str]:
    # Официальная страница отдаёт редирект на changeable download id — вытаскиваем
    # текущий URL json-файла Service Tags (Public cloud) со страницы подтверждения.
    page = http_get(
        "https://www.microsoft.com/en-us/download/details.aspx?id=56519"
    ).decode(errors="ignore")
    m = re.search(r'https://download\.microsoft\.com/download/[^"\']+ServiceTags_Public[^"\']+\.json', page)
    if not m:
        raise RuntimeError("microsoft: не удалось найти ссылку на ServiceTags_Public JSON")
    data = json.loads(http_get(m.group(0)))
    prefixes = []
    for value in data["values"]:
        prefixes.extend(value["properties"].get("addressPrefixes", []))
    return prefixes


# --- ASN-based ---------------------------------------------------------

ASN_SERVICES: dict[str, list[int]] = {
    "meta": [32934, 63293, 54115],           # Facebook, Facebook-Offnet, Facebook-Corp
    "twitter": [13414],                       # Twitter/X
    "netflix": [2906, 40027, 55095],          # Netflix Inc + Open Connect
    "youtube_google": [15169, 19527, 36040],  # Google, Google-2, YouTube (без AS396982=GCP, это чужой шаринг!)
    "linkedin": [14413],
    "tiktok": [138699],
    "railway": [400940],
    "openai": [401518],                       # у OpenAI своих префиксов почти нет, см. README
    "anthropic": [399358],                    # claude.ai, api/console.anthropic.com — свой ASN, не CDN
}

# Официальные фиды: имя_файла -> функция
OFFICIAL_SERVICES = {
    "telegram": fetch_telegram,
    "cloudflare": fetch_cloudflare,
    "amazon": fetch_amazon,
    "microsoft": fetch_microsoft,
}

# Сервисы без надёжного списка по IP (общий CDN/хостинг у третьих лиц) —
# файлы не генерируются, только заметка в README.
SHARED_INFRA_NOTES = {
    "discord": "Голос/CDN идут через Cloudflare и i3D.net (AS49544) — тот же ASN хостит множество других клиентов i3D, точный список по IP невозможен без ложных срабатываний.",
    "pornhub": "Aylo/Pornhub отдаётся через стороннего хостера (Reflected Networks), выделенного ASN нет.",
    "openai_web": "chatgpt.com/chat-фронтенд идёт через Cloudflare (общий anycast) — своя выделенная сеть (AS401518) покрывает лишь малую часть инфраструктуры.",
}

# Домены для сервисов без выделенного ASN (см. SHARED_INFRA_NOTES) плюс
# отдельно запрошенные ресурсы. Не резолвятся здесь: IP из гео-локации
# GitHub Actions runner-а не совпадали бы с тем, что реально видит клиент.
# Вместо этого домены добавляются как FQDN прямо в address-list на MikroTik —
# RouterOS сам резолвит и держит IP актуальными (см. mikrotik/README.md).
DOMAIN_SERVICES: dict[str, list[str]] = {
    "discord": [
        "discord.com", "discordapp.com", "discord.gg",
        "cdn.discordapp.com", "media.discordapp.net", "gateway.discord.gg",
    ],
    "pornhub": ["pornhub.com", "www.pornhub.com"],
    "openai_web": [
        "openai.com", "chatgpt.com", "chat.openai.com", "api.openai.com",
        "cdn.oaistatic.com", "ab.chatgpt.com",
    ],
    "resend": ["resend.com", "api.resend.com"],
    "atakdomain": ["atakdomain.com", "www.atakdomain.com"],
}

# Какие файлы из data/*.txt имеет смысл реально заворачивать в VPN/wg2.
# amazon и microsoft — это весь адресный пул облака целиком (не конкретный
# сервис), заворачивать их в туннель означает пустить туда любой сайт на
# AWS/Azure — исключены из "routable", оставлены в репо для справки.
ROUTABLE_CIDR_SERVICES = [
    "meta", "telegram", "cloudflare", "twitter", "netflix",
    "youtube_google", "linkedin", "tiktok", "railway", "openai", "anthropic",
]
NON_ROUTABLE_CIDR_SERVICES = ["amazon", "microsoft"]


def write_service_file(name: str, prefixes: list[str], source_note: str) -> None:
    out = DATA_DIR / f"{name}.txt"
    lines = dedupe_and_sort(prefixes)
    out.write_text(f"# source: {source_note}\n# generated by scripts/fetch.py — do not edit by hand\n" + "\n".join(lines) + "\n")
    print(f"{name}: {len(lines)} prefixes -> {out.relative_to(ROOT)}")


def write_domains_file() -> None:
    out = DATA_DIR / "domains.txt"
    parts = ["# generated by scripts/fetch.py — do not edit by hand",
             "# FQDN-и для сервисов без выделенного ASN (общий CDN) — на MikroTik",
             "# добавляются напрямую в address-list как имя домена, не резолвятся здесь."]
    for name, domains in DOMAIN_SERVICES.items():
        parts.append(f"# {name}")
        parts.extend(domains)
    out.write_text("\n".join(parts) + "\n")
    total = sum(len(d) for d in DOMAIN_SERVICES.values())
    print(f"domains: {total} domains -> {out.relative_to(ROOT)}")


def write_manifest() -> None:
    manifest = {
        "routable_cidr_services": ROUTABLE_CIDR_SERVICES,
        "non_routable_cidr_services": NON_ROUTABLE_CIDR_SERVICES,
        "domain_services": list(DOMAIN_SERVICES.keys()),
    }
    out = DATA_DIR / "manifest.json"
    out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(f"manifest -> {out.relative_to(ROOT)}")


def _rsc_group(comment: str, addresses: list[str]) -> list[str]:
    lines = [
        f'/ip firewall address-list remove '
        f'[/ip firewall address-list find where list="{ADDRESS_LIST_NAME}" and comment="{comment}"]'
    ]
    for addr in addresses:
        lines.append(
            f'/ip firewall address-list add list={ADDRESS_LIST_NAME} address="{addr}" comment="{comment}"'
        )
    return lines


def write_mikrotik_script() -> None:
    """Готовый .rsc для /import на MikroTik: полностью пересобирает address-list
    wg2-nets из ROUTABLE_CIDR_SERVICES + доменов (amazon/microsoft сюда не входят —
    см. NON_ROUTABLE_CIDR_SERVICES). Каждая группа сначала чистится по comment,
    затем наполняется заново — так router.rsc сам решает add/remove, без diff-логики
    в RouterOS-скрипте (он медленный на больших циклах)."""
    MIKROTIK_DIR.mkdir(exist_ok=True)
    out_lines = [
        "# АВТОГЕНЕРИРУЕТСЯ scripts/fetch.py — не редактировать руками.",
        "# Импортировать на MikroTik: /import file-name=wg2-nets.rsc",
        f"# Полностью пересобирает группы address-list \"{ADDRESS_LIST_NAME}\" по comment=src:<service>.",
    ]
    for name in ROUTABLE_CIDR_SERVICES:
        f = DATA_DIR / f"{name}.txt"
        addrs = [l for l in f.read_text().splitlines() if l and not l.startswith("#")]
        out_lines.append(f"\n# --- {name} ({len(addrs)}) ---")
        out_lines.extend(_rsc_group(f"src:{name}", addrs))

    domains: list[str] = []
    for group in DOMAIN_SERVICES.values():
        domains.extend(group)
    out_lines.append(f"\n# --- domains ({len(domains)}) ---")
    out_lines.extend(_rsc_group("src:domains", domains))

    out = MIKROTIK_DIR / "wg2-nets.rsc"
    out.write_text("\n".join(out_lines) + "\n")
    print(f"mikrotik script -> {out.relative_to(ROOT)}")


def main() -> int:
    DATA_DIR.mkdir(exist_ok=True)
    had_errors = False

    for name, fn in OFFICIAL_SERVICES.items():
        try:
            write_service_file(name, fn(), "official feed")
        except Exception as e:  # noqa: BLE001
            print(f"[ERROR] {name}: {e}", file=sys.stderr)
            had_errors = True

    for name, asns in ASN_SERVICES.items():
        try:
            prefixes: list[str] = []
            for asn in asns:
                prefixes.extend(ripestat_prefixes(asn))
            asn_list = ", ".join(f"AS{a}" for a in asns)
            write_service_file(name, prefixes, f"RIPEstat announced-prefixes for {asn_list}")
        except Exception as e:  # noqa: BLE001
            print(f"[ERROR] {name}: {e}", file=sys.stderr)
            had_errors = True

    write_domains_file()
    write_manifest()
    write_mikrotik_script()

    # combined file — только CIDR-файлы (domains.txt не CIDR, all.txt сам себе не источник)
    all_prefixes: list[str] = []
    for f in sorted(DATA_DIR.glob("*.txt")):
        if f.name in ("all.txt", "domains.txt"):
            continue
        for line in f.read_text().splitlines():
            if line and not line.startswith("#"):
                all_prefixes.append(line)
    write_service_file("all", all_prefixes, "combined from all data/*.txt (без domains.txt)")

    return 1 if had_errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
