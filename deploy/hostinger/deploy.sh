#!/usr/bin/env bash
# Nimmt einen fertig gebauten Flutter-Web-Stand (tar.gz über stdin) entgegen
# und macht ihn live. Liegt auf dem Server als /docker/lerndex-app/deploy.sh.
#
#   tar czf - -C build/web . | ssh nils-vps /docker/lerndex-app/deploy.sh
#
# Aufgerufen von tool/deploy/web_hostinger.sh (lokal) bzw. später von der
# GitHub Action. Vorlage: /docker/fahrsignal/deploy.sh.
set -euo pipefail

BASIS=/docker/lerndex-app/site
STAND=$(date +%Y%m%d-%H%M%S)
NEU="$BASIS/releases/$STAND"
LOG=/docker/lerndex-app/deploy.log

protokoll() { echo "$(date '+%F %T')  $*" >> "$LOG"; }

mkdir -p "$NEU"
trap 'rm -rf "$NEU"' ERR
tar xzf - -C "$NEU"

# Lieber den alten Stand weiter ausliefern als einen kaputten neuen.
for pflicht in index.html main.dart.js flutter_bootstrap.js canvaskit/canvaskit.wasm; do
    if [ ! -s "$NEU/$pflicht" ]; then
        protokoll "ABBRUCH $STAND - $pflicht fehlt, alter Stand bleibt live"
        echo "Abbruch: $pflicht fehlt" >&2
        exit 1
    fi
done
chmod -R a+rX "$NEU"

# Atomarer Schwenk, relatives Ziel (im Container ist site/ unter /srv).
ln -sfn "releases/$STAND" "$BASIS/www.neu"
mv -T "$BASIS/www.neu" "$BASIS/www"
trap - ERR

# Die letzten fünf Stände bleiben zum Zurückschwenken liegen:
#   cd /docker/lerndex-app/site && ln -sfn releases/<stand> www.neu && mv -T www.neu www
ls -1dt "$BASIS"/releases/*/ 2>/dev/null | tail -n +6 | xargs -r rm -rf

protokoll "$STAND live ($(du -sh "$NEU" | cut -f1))"
echo "Lerndex: $STAND ist live"
