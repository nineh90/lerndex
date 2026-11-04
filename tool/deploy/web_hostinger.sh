#!/usr/bin/env bash
# Web-App auf app.lerndex.de (Nils' Hostinger-VPS) deployen.
#
#   tool/deploy/web_hostinger.sh           # bauen und ausliefern
#   tool/deploy/web_hostinger.sh --setup   # nginx/Compose auf dem Server aktualisieren
#                                          # und Container (neu) starten
#
# Baut nur den Branch "schule" ohne offene Änderungen, immer mit leerem
# Build-Cache (am 01.11.2026 lief sonst ein alter Stand live). SSH-Ziel ist
# der Host "nils-vps" aus ~/.ssh/config (Benutzer kevin).
set -euo pipefail
cd "$(dirname "$0")/../.."

SERVER=${LERNDEX_SERVER:-nils-vps}
ZIEL=/docker/lerndex-app
URL=https://app.lerndex.de

if [ "${1:-}" = "--setup" ]; then
    echo "→ Server-Konfiguration nach $SERVER:$ZIEL"
    scp -q deploy/hostinger/docker-compose.yml deploy/hostinger/nginx.conf "$SERVER:$ZIEL/deploy/"
    scp -q deploy/hostinger/deploy.sh "$SERVER:$ZIEL/deploy.sh"
    ssh "$SERVER" "chmod +x $ZIEL/deploy.sh && cd $ZIEL/deploy && docker compose up -d && docker exec lerndex-app nginx -t"
    exit 0
fi

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "schule" ]; then
    echo "Abbruch: Deploy nur aus dem Branch schule (aktuell: $branch)" >&2; exit 1
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "Abbruch: offene Änderungen, bitte erst committen" >&2; exit 1
fi

export PATH="$HOME/flutter/bin:$PATH"
echo "→ Baue $(git log --oneline -1)"
rm -rf .dart_tool/flutter_build build/web
flutter build web --no-web-resources-cdn --dart-define-from-file=dart-defines.json

# Große Dateien vorkomprimieren (nginx gzip_static), spart Mobilfunk
find build/web -type f -size +1k \
    \( -name '*.js' -o -name '*.wasm' -o -name '*.json' -o -name '*.css' \
       -o -name '*.svg' -o -name '*.otf' -o -name '*.ttf' \) \
    -exec gzip -9 -k -f {} +
du -sh build/web

echo "→ Ausliefern an $SERVER"
tar czf - -C build/web . | ssh "$SERVER" "$ZIEL/deploy.sh"

for pfad in / /k/TEST2345 /main.dart.js; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$URL$pfad")
    echo "  $code  $URL$pfad"
    [ "$code" = 200 ] || { echo "Prüfung fehlgeschlagen" >&2; exit 1; }
done
echo "✓ $URL ist aktuell"
