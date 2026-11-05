#!/usr/bin/env python3
"""Abo-Status aller Elternkonten einmal bei RevenueCat abgleichen.

    python3 tool/admin/abo_abgleich.py            # nur zeigen, welche Konten
    python3 tool/admin/abo_abgleich.py --los      # abgleichen

Für die Umstellung auf den Server-Abgleich (functions/subscription.js): Bis
dahin hat die Android-App den Status selbst gespeichert. Das Skript schickt
für jedes Konto mit `subscription`-Feld ein Ereignis an die Function
revenuecatWebhook; die holt den echten Status bei RevenueCat und speichert
ihn. Die Logik steht damit nur an einer Stelle.

Zugang: Login der Firebase-CLI; das Webhook-Geheimnis liest das Skript per
`firebase functions:secrets:access REVENUECAT_WEBHOOK_AUTH`.
"""
import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

PROJECT = "lerndex-3775f"
CONFIG = Path.home() / ".config/configstore/firebase-tools.json"
QUERY = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents:runQuery"
WEBHOOK = f"https://europe-west3-{PROJECT}.cloudfunctions.net/revenuecatWebhook"


def token():
    subprocess.run(["firebase", "projects:list"], capture_output=True, timeout=120)
    try:
        return json.loads(CONFIG.read_text())["tokens"]["access_token"]
    except (OSError, KeyError, ValueError):
        sys.exit("Kein Firebase-Login gefunden. Bitte zuerst: firebase login")


def accounts_with_subscription(access):
    body = {"structuredQuery": {
        "from": [{"collectionId": "users"}],
        "select": {"fields": [{"fieldPath": "subscription"}]},
    }}
    req = urllib.request.Request(QUERY, data=json.dumps(body).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {access}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as resp:
        rows = json.loads(resp.read())
    uids = []
    for row in rows:
        doc = row.get("document")
        if doc and "subscription" in doc.get("fields", {}):
            uids.append(doc["name"].rsplit("/", 1)[-1])
    return uids


def webhook_secret():
    out = subprocess.run(
        ["firebase", "functions:secrets:access", "REVENUECAT_WEBHOOK_AUTH", "--project", PROJECT],
        capture_output=True, text=True, timeout=120,
    )
    secret = out.stdout.strip().splitlines()[-1] if out.stdout.strip() else ""
    if out.returncode != 0 or not secret:
        sys.exit("Webhook-Geheimnis nicht lesbar: " + (out.stderr.strip()[:300] or "leer"))
    return secret


def sync(uid, secret):
    body = {"event": {"type": "LERNDEX_ABGLEICH", "app_user_id": uid}}
    req = urllib.request.Request(WEBHOOK, data=json.dumps(body).encode(), method="POST")
    req.add_header("Authorization", f"Bearer {secret}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        return e.code


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--los", action="store_true", help="wirklich abgleichen")
    args = parser.parse_args()
    uids = [u for u in accounts_with_subscription(token()) if not u.startswith("school_")]
    print(f"{len(uids)} Konten mit gespeichertem Abo-Status.")
    if not args.los:
        print("Zum Abgleichen: --los")
        return
    secret = webhook_secret()
    failed = 0
    for uid in uids:
        status = sync(uid, secret)
        if status != 200:
            failed += 1
            print(f"  {uid}: Fehler {status}")
    print(f"Fertig, {len(uids) - failed} abgeglichen, {failed} Fehler.")


if __name__ == "__main__":
    main()
