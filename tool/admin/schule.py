#!/usr/bin/env python3
"""Schulen verwalten (nur für Lerndex selbst, nicht Teil der App).

    python3 tool/admin/schule.py einladen [--name "Grundschule am Wald"] [--bis 2027-07-31] [--tage 30]
    python3 tool/admin/schule.py lizenz SCHUL_ID 2027-07-31
    python3 tool/admin/schule.py liste

einladen  Einmal-Link für eine Schule (…/schule/CODE). Die Schulleitung
          registriert sich darüber, die Schule ist danach bis --bis
          freigeschaltet. Ohne --name gibt die Schule ihren Namen selbst ein.
          Der Link gilt --tage Tage (Standard 30).
lizenz    Lizenz einer bestehenden Schule setzen oder verlängern.
liste     Schulen mit Lizenz und Lehrkräften, offene Einladungen.

Zugang: der Login der Firebase-CLI (firebase login). Läuft der Zugang ab,
holt das Skript ihn über die CLI neu.
"""
import argparse
import datetime as dt
import json
import secrets
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from zoneinfo import ZoneInfo

PROJECT = "lerndex-3775f"
WEB_APP = "https://lerndex-3775f.web.app"
DB = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
CONFIG = Path.home() / ".config/configstore/firebase-tools.json"
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # wie functions/lib/helpers.js
BERLIN = ZoneInfo("Europe/Berlin")


def _token(refresh=False):
    if refresh:
        # Jeder CLI-Befehl mit Anmeldung erneuert den gespeicherten Zugang
        subprocess.run(
            ["firebase", "projects:list"], capture_output=True, timeout=120
        )
    try:
        return json.loads(CONFIG.read_text())["tokens"]["access_token"]
    except (OSError, KeyError, ValueError):
        sys.exit("Kein Firebase-Login gefunden. Bitte zuerst: firebase login")


def api(method, url, body=None, _retry=True):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {_token(refresh=not _retry)}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        if e.code == 401 and _retry:
            return api(method, url, body, _retry=False)
        if e.code == 404:
            return None
        sys.exit(f"Fehler {e.code}: {e.read().decode()[:400]}")


def end_of_day(date_text):
    """JJJJ-MM-TT → 23:59:59 deutscher Zeit als UTC-Zeitstempel."""
    try:
        day = dt.date.fromisoformat(date_text)
    except ValueError:
        sys.exit(f"Datum bitte als JJJJ-MM-TT, nicht „{date_text}“.")
    local = dt.datetime.combine(day, dt.time(23, 59, 59), BERLIN)
    return local.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ts(value):
    return {"timestampValue": value}


def show_date(field):
    if not field or "timestampValue" not in field:
        return "—"
    return field["timestampValue"][:10]


def cmd_einladen(args):
    code = "".join(secrets.choice(ALPHABET) for _ in range(8))
    expires = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=args.tage))
    fields = {
        "createdAt": ts(dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")),
        "expiresAt": ts(expires.strftime("%Y-%m-%dT%H:%M:%SZ")),
    }
    if args.name:
        fields["schoolName"] = {"stringValue": args.name.strip()}
    if args.bis:
        fields["licenseUntil"] = ts(end_of_day(args.bis))
    api("PATCH", f"{DB}/schoolSignups/{code}?currentDocument.exists=false",
        {"fields": fields})
    print(f"Einladungslink: {WEB_APP}/schule/{code}")
    print(f"Gültig bis {expires.astimezone(BERLIN):%d.%m.%Y}, nur einmal nutzbar.")
    print(f"Lizenz: bis {args.bis}" if args.bis else
          "Lizenz: keine (später mit „lizenz SCHUL_ID DATUM“ setzen)")


def cmd_lizenz(args):
    doc = f"{DB}/users/school_{args.schul_id}"
    if api("GET", doc) is None:
        sys.exit(f"Keine Schule mit der ID {args.schul_id} (siehe „liste“).")
    api("PATCH", f"{doc}?updateMask.fieldPaths=schoolLicenseUntil&currentDocument.exists=true",
        {"fields": {"schoolLicenseUntil": ts(end_of_day(args.datum))}})
    print(f"Schule {args.schul_id} freigeschaltet bis {args.datum}.")


def cmd_liste(_args):
    schools = (api("GET", f"{DB}/schools?pageSize=300") or {}).get("documents", [])
    if not schools:
        print("Noch keine Schulen.")
    for s in schools:
        sid = s["name"].rsplit("/", 1)[-1]
        name = s["fields"].get("name", {}).get("stringValue", "")
        owner = api("GET", f"{DB}/users/school_{sid}") or {"fields": {}}
        licence = show_date(owner["fields"].get("schoolLicenseUntil"))
        print(f"{name}  (ID {sid})  Lizenz bis {licence}")
        members = (api("GET", f"{DB}/schools/{sid}/members?pageSize=300") or {}).get("documents", [])
        for m in members:
            f = m["fields"]
            role = "Schulleitung" if f.get("role", {}).get("stringValue") == "admin" else "Lehrkraft"
            print(f"    {f.get('email', {}).get('stringValue', '?')}  {role}")
    signups = (api("GET", f"{DB}/schoolSignups?pageSize=300") or {}).get("documents", [])
    if signups:
        print("\nOffene Einladungen:")
        for s in signups:
            code = s["name"].rsplit("/", 1)[-1]
            f = s["fields"]
            name = f.get("schoolName", {}).get("stringValue", "(Name gibt die Schule ein)")
            print(f"    {WEB_APP}/schule/{code}  {name}  gültig bis "
                  f"{show_date(f.get('expiresAt'))}, Lizenz bis {show_date(f.get('licenseUntil'))}")


def main():
    parser = argparse.ArgumentParser(description="Lerndex-Schulen verwalten")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("einladen", help="Einladungslink für eine Schule")
    p.add_argument("--name", help="Name der Schule (sonst gibt ihn die Schule ein)")
    p.add_argument("--bis", help="Lizenz bis JJJJ-MM-TT")
    p.add_argument("--tage", type=int, default=30, help="Link gültig für so viele Tage")
    p.set_defaults(fn=cmd_einladen)
    p = sub.add_parser("lizenz", help="Lizenz setzen oder verlängern")
    p.add_argument("schul_id")
    p.add_argument("datum", help="JJJJ-MM-TT")
    p.set_defaults(fn=cmd_lizenz)
    p = sub.add_parser("liste", help="Schulen und offene Einladungen")
    p.set_defaults(fn=cmd_liste)
    args = parser.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
