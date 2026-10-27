# Plan: Lerndex für Schulen und als Web-App

Stand: 27.10.2026, Branch `web`

Anlass: Eine Schule testet Lerndex. Wünsche der Lehrerin:

- Lexi soll vorlesen, für alle Jahrgänge, besonders für Kinder mit Förderbedarf.
- Nutzung in Lernzeiten: alle Kinder der Schule eingepflegt, alle Lehrkräfte sehen alle Klassen.
- Arbeitsverhalten (grün/gelb/rot) eintragen, daraus Stufen mit Auf- und Abstieg und
  schulinterne Privilegien („freier Platz“ bis „zu Hause arbeiten“), nur auf Lernzeiten bezogen.
- Kind aufs eigene Handy bringen, am liebsten per Code oder QR.

Entscheidungen:

- **Eine App mit Rollen** (Eltern, Lehrkraft, Schüler) statt zwei Apps.
- **Zuerst Web.** Flutter Web aus demselben Code. Läuft auf iPhone und PC ohne App Store,
  die Play-Store-App bleibt.
- **Laravel-Backend als letzte Phase**, wenn der Schulvertrag steht.

---

## Phase 1: Web-Version ✅ (Branch `web`)

Erledigt:

- Crashlytics, Native-Splash und Hochformat-Sperre laufen nur in den Apps.
- Fotos (Tutor, Aufgaben aus Foto, Feedback) als `XFile`/Bytes statt `dart:io File`.
- `Platform.isIOS` ersetzt durch `lib/src/shared/platform_info.dart`.
- Google-Login im Browser per Firebase-Popup, Apple-Button nur in der iOS-App.
- RevenueCat im Web über `REVENUECAT_WEB_KEY` (Web Billing/Stripe). Ohne Key bleiben die
  Käufe aus, die App läuft trotzdem. „Abo verwalten“ öffnet die Seite des Stores, in dem
  gekauft wurde.
- App Check mit reCAPTCHA Enterprise im Web über `RECAPTCHA_SITE_KEY`.
- Eigenes Hintergrundbild im Browser ausgeblendet, weil es als Datei im App-Verzeichnis liegt.
- `web/`: Icons, Manifest (zum Home-Bildschirm hinzufügbar), Ladebildschirm.
- `firebase.json`: Firebase Hosting mit `build/web`.
- Keine fremden Server beim Start (siehe unten „Fremde Server im Browser“).

Offen, nur Kevin kann das machen (Konsolen und Zugänge):

1. **reCAPTCHA Enterprise / App Check:** Firebase Console → App Check → Web-App registrieren →
   Site-Key als `RECAPTCHA_SITE_KEY` in `dart-defines.json` eintragen.
   Die **Erzwingung (Enforcement) erst einschalten, wenn auch Android App Check hat.**
   Sonst funktioniert die KI in der Play-Store-App nicht mehr.
2. **Domain:** z.B. `app.lerndex.de` in Firebase Hosting anbinden und unter
   Authentication → Einstellungen → Autorisierte Domains eintragen.
   `authDomain` in `firebase_options.dart` (web) auf diese Domain setzen. Sonst kann der
   Google-Login in Safari scheitern, weil Safari Cookies fremder Domains blockiert.
3. **RevenueCat Web Billing:** Stripe verbinden, Web-Produkte anlegen, Web-API-Key als
   `REVENUECAT_WEB_KEY` eintragen. Für die Schule nicht nötig, dort per Rechnung.
   Dann zusätzlich die Import-Map in `web/index.html` entfernen (sonst bleibt RevenueCat im
   Browser abgeschaltet) und vorher klären, ob dafür ein Cookie-/Einwilligungsbanner nötig
   ist: Stripe.js lädt Telemetrie von Stripe-Servern.
4. **Deploy:**
   `flutter build web --no-web-resources-cdn --dart-define-from-file=dart-defines.json`
   und dann `firebase deploy --only hosting`. Ohne `--no-web-resources-cdn` lädt der Browser
   die Grafik-Engine von www.gstatic.com.
5. **Testen auf echten Geräten:** iPhone mit Safari, Android mit Chrome, ein Schul-Tablet,
   ein PC. Besonders Tastatur, Kamera (Foto im Tutor), Mikrofon und Vorlesen prüfen.

Bekannte Einschränkungen im Browser:

- Erster Start lädt einige MB, danach kommt alles aus dem Cache.
- Spracheingabe gibt es in Chrome und Safari, aber nicht in Firefox.
- Safari spricht erst nach dem ersten Tipp. Das ist abgefangen: Der Tipp auf „Senden“ bzw. auf
  den Vorlesen-Schalter schaltet die Ausgabe frei.

### Fremde Server im Browser

Flutter Web und einige Plugins laden standardmäßig Dateien von fremden Servern. Für eine App,
die Kinder in der Schule nutzen, ist das abgestellt:

| Was | Vorher | Jetzt |
|---|---|---|
| Grafik-Engine (CanvasKit) | www.gstatic.com | lokal, Build mit `--no-web-resources-cdn` |
| Schrift Roboto, Emojis, Symbole | fonts.gstatic.com | lokal aus `web/fonts/` (`fontFallbackBaseUrl`) |
| RevenueCat-Skript | cdn.jsdelivr.net, lädt Stripe.js nach | leeres Modul per Import-Map in `web/index.html` |

`test/web/web_third_party_test.dart` schlägt an, wenn ein Update von `purchases_flutter`
die Skript-Adresse ändert.

Noch offen, beides Google und Teil von Firebase:

- `www.gstatic.com/firebasejs/…`: Das Firebase-JS-SDK, das FlutterFire im Browser nachlädt.
  Ließe sich selbst hosten.
- `accounts.google.com/gsi/client`: Das google_sign_in-Plugin lädt das Google-Login-Skript beim
  Start, obwohl der Web-Login über Firebase läuft.

## Phase 2: Lexi vorlesen ✅ (Branch `web`)

- Lautsprecher-Knopf an jeder Lexi-Nachricht (vorlesen, nochmal tippen = stopp).
- Schalter in der Tutor-Kopfzeile: „Automatisch vorlesen“, pro Kind gespeichert, Standard aus.
- `speakableText()` übersetzt Markdown, Formeln (`$\frac{1}{2}$` → „1 geteilt durch 2“) und
  Emojis in sprechbaren Text.
- Fehler behoben: Die Sprachausgabe startete im Browser gar nicht, weil das Plugin intern
  `Platform.isIOS` abfragt.

Später möglich: Quizfragen im Standard-Modus (ab Klasse 3) vorlesen. Eine bessere Stimme
(Cloud-TTS in der EU) statt der Gerätestimme.

## Phase 3: Rollen und Sicherheit

Heute hängt alles am Eltern-Account (`users/{uid}/children/{childId}`). Ein Kind hat keinen
eigenen Login. 113 Stellen in 31 Dateien greifen fest auf `collection('users')` zu.

1. Cloud Functions einführen. Rollen als Custom Claims am Token: `parent`, `teacher`,
   `student`, `schoolAdmin` plus `schoolId`.
2. Firestore- und Storage-Rules pro Rolle neu schreiben. Das erledigt die offenen Punkte
   PIN-Prüfung und Abo-Status serverseitig.
3. Datenzugriff hinter einen Provider legen („wo liegt das aktuelle Lernprofil?“), statt fester
   Pfade. **Wichtig für Phase 6:** Dann lässt sich das Backend später tauschen.
4. **QR-Kopplung fürs Kindergerät:** Eltern zeigen einen QR-Code mit einem Link
   (`app.lerndex.de/k/…`), das Kind scannt ihn mit der Handykamera und ist als Schüler
   angemeldet. Kein Eltern-Passwort auf dem Kinderhandy, kein Zugang zum Elternbereich.

## Phase 4: Schule

```
schools/{schoolId}                    Name, Lizenz
schools/{sid}/members/{uid}           role: admin | teacher
schools/{sid}/classes/{classId}       "5b", Jahrgang
schools/{sid}/students/{studentId}    wie ChildModel + classId
```

- Ein Schul-Admin lädt Lehrkräfte per Mail ein. Alle Lehrkräfte sehen alle Klassen.
- Schüler per CSV/Excel-Import.
- Schüler-Login über ausdruckbare QR-Karten. Auf geteilten Tablets schneller Kinderwechsel.
- Schullizenz per Rechnung. Freischaltung über die Schulzugehörigkeit, serverseitig gesetzt.

Vorher klären: **Auftragsverarbeitungsvertrag (AVV)** mit Schule bzw. Schulträger, Zustimmung
des Datenschutzbeauftragten. Klären, ob Lehrkräfte die Lexi-Chats der Kinder sehen dürfen.

## Phase 5: Arbeitsverhalten, Stufen, Privilegien

- Lehrer-Ansicht „Lernzeit“: Klassenliste mit drei Knöpfen pro Kind (grün, gelb, rot).
  Ziel: 25 Kinder in unter einer Minute.
- Eigenes Stufensystem, getrennt von XP (XP steigen nur, Stufen können sinken).
- Privilegien legt die Schule selbst an. Das Kind sieht seine Stufe und was als Nächstes kommt.

Fürs Telefonat mit der Lehrerin:

- Wie viele Stufen? Wie viele grüne Bewertungen bis zur nächsten Stufe?
- Was bewirkt Rot: eine Stufe runter oder zurück auf null?
- Wird pro Lernzeit oder pro Tag bewertet?
- Sehen Kinder und Eltern die Bewertung?
- Wie viele Schüler, Lehrkräfte, Klassen? Eigene Handys oder Schul-Tablets?
- Woher kommt die Schülerliste (Exportformat der Schulverwaltung)?

## Phase 6: Laravel-Backend (wenn der Schulvertrag steht)

Flutter bleibt die Oberfläche (Web und Android). Die Daten wandern aus Firestore in ein
Laravel-Backend mit MySQL.

Gewinn:

- Die Schulstruktur (Schule, Klassen, Schüler, Rollen) passt in Tabellen mit Beziehungen
  deutlich sauberer als in Firestore.
- Rollen prüft der Server selbst, keine Custom Claims und Rules mehr.
- KI-Aufrufe laufen nur auf dem Server, kein Schlüssel mehr im Browser.
- Hosting in Deutschland (Hostinger), das erleichtert das Datenschutz-Gespräch mit Schulen.
- Gleicher Stack wie Pflegedex.

Aufwand: Die ganze Datenschicht inklusive Echtzeit-Streams wird ersetzt. Deshalb in Phase 3
den Datenzugriff zentral bündeln, dann ist es ein Austausch an einer Stelle statt an 113.
