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
4. **Deploy:** `rm -rf .dart_tool/flutter_build build/web`, dann
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

## Stand Deploy (01.11.2026)

- Functions (14) deployt, öffentlich aufrufbar über „ohne IAM-Prüfung“ (Firmenrichtlinie verbietet
  `allUsers`). Beim nächsten `npm run deploy` meldet die CLI, sie könne den Invoker nicht setzen –
  danach prüfen, ob die Functions noch antworten.
- Firestore- und Storage-Regeln live (über die Rules-API; die CLI scheitert an fehlendem
  `serviceusage`-Recht von Kevins Konto). Vorherige Fassung: `docs/rules-backup/`.
- Web-App live: https://lerndex-3775f.web.app

## Phase 3: Rollen und Sicherheit ✅

Erledigt:

- **Konto-Abstraktion** (`lib/src/features/auth/domain/account.dart`): Alle Datenpfade nutzen
  `user.ownerUid` statt `user.uid`. Für Eltern ist das dieselbe ID. Ein gekoppeltes Kindergerät
  hat ein eigenes Konto `kid:<parentUid>:<childId>`, seine Daten liegen weiter bei den Eltern.
  Bei der Schul-Struktur (Phase 4) bzw. dem Laravel-Backend (Phase 6) ist das die eine Stelle,
  an der festgelegt wird, wem die Daten gehören.
- **Cloud Functions** (`functions/index.js`, Region europe-west3):
  - `createPairingCode`, `redeemPairingCode`, `unpairChildDevices`: Kindergerät koppeln.
    Code mit 8 Zeichen, 15 Minuten gültig, nur einmal nutzbar. Das Kinderkonto bekommt die
    Claims `{ role: "student", parentUid, childId }`. Abmelden löscht das Kinderkonto.
  - `setParentPin`, `verifyParentPin`: PIN auf dem Server. Hash in `users/{uid}/private/pin`,
    das kein Client lesen kann. Sperre nach 5 Fehlversuchen. Alte Hashes im users-Dokument
    werden beim ersten Prüfen dorthin umgezogen (gleiches Hash-Verfahren, getestet).
  - `cleanupDeletedParent` (Auth-Trigger): Beim Löschen eines Elternkontos PIN und offene
    Codes entfernen.
- **Rules:** Ein Kindergerät darf nur sein eigenes Kind lesen und speichern, das Eltern-
  Dokument lesen (Abo-Status) und die freigegebenen Aufgaben seines Kindes. Kein Geschwister-
  kind, kein PIN, keine Geräteliste, kein Kind anlegen oder löschen.
- **App:**
  - Elternbereich: Kind-Menü → „Gerät verbinden“ zeigt QR-Code und Code. Unter „Kind
    bearbeiten → Eigenes Gerät“ stehen die verbundenen Geräte und „Alle abmelden“.
  - Anmeldeseite: „Ich bin ein Kind – Code eingeben“.
  - Link `…/k/CODE` aus dem QR-Code löst den Code im Browser sofort ein.
  - Ein Kindergerät startet direkt im Kinder-Dashboard, ohne Zurück-Knopf und ohne
    Elternbereich.
- **Abo-Status:** Ohne RevenueCat (Browser ohne Web-Key) und auf Kindergeräten gilt der Status
  aus Firestore. Vorher hätten zahlende Familien im Browser ihr Abo „verloren“.
- **Tests:** 30 Tests im Emulator (`functions/`, siehe unten) und 272 Flutter-Tests.

### Deploy-Reihenfolge (wichtig)

Vorher: `firebase login --reauth`, die gespeicherte Anmeldung ist abgelaufen.

1. **Functions:** `cd functions && npm run deploy`. Deployt **nur unsere Functions mit Namen**.
   Im Projekt laufen schon `waitlist` (europe-west10, Website-Warteliste, nicht in diesem Repo)
   und die E-Mail-Erweiterung. Ein nacktes `firebase deploy --only functions` würde anbieten,
   `waitlist` zu löschen. Neue Function? Dann `npm run deploy` in package.json ergänzen.
   Blaze-Tarif ist aktiv.
2. **IAM:** Das Dienstkonto der Functions muss Custom Tokens signieren dürfen. In der Google
   Cloud Console unter IAM dem Konto `<Projektnummer>-compute@developer.gserviceaccount.com`
   die Rolle **„Service Account Token Creator“** geben und die API „IAM Service Account
   Credentials“ aktivieren. Ohne das scheitert `redeemPairingCode`.
3. **Rules:** `firebase deploy --only firestore:rules,storage`. Live ist (geprüft 28.10.2026 in
   der Console) exakt der Stand von `release-1.1.5` vom 16.07.2026, Sicherung in
   `docs/rules-backup/`. Zurück geht es in der Console über den Regel-Verlauf. Die neuen Rules sind mit der aktuellen Play-Store-Version
   verträglich (Übergangsregel für den alten Client-PIN in `firestore.rules`).
4. **App:** Erst danach Web und Android mit dieser Version ausrollen. Die neue App prüft den PIN
   nur noch über die Function. Ohne deployte Functions kommt niemand mehr in den Elternbereich.
5. **Später:** Wenn alle Android-Nutzer auf der neuen Version sind, in `functions/index.js`
   `LEGACY_PIN_MIRROR = false` setzen und die Übergangsregel für `hashedPin`/`pinSalt` in
   `firestore.rules` entfernen. Bis dahin schreibt der Server den PIN zusätzlich im alten Format,
   sonst böte die alte Play-Store-App „PIN einrichten“ an und ein Kind könnte einen eigenen PIN
   setzen.

### Testen

```bash
cd functions
npm install
JAVA_HOME=~/jdks/current npm run test:emulator   # Rules + Functions im Emulator
```

Die App gegen die Emulatoren (ohne echte Daten):

```bash
firebase emulators:start --project lerndex-3775f --only auth,firestore,functions,storage
flutter run -d chrome --dart-define-from-file=dart-defines.json --dart-define=USE_FIREBASE_EMULATOR=true
```

Im Browser geht die Anmeldung mit dem Emulator beim Neuladen verloren: Firebase prüft das
gespeicherte Konto dann gegen den echten Server. Mit echten Konten passiert das nicht.

### Offen

- **Abo serverseitig:** Den Abo-Status schreibt weiterhin die App (`_syncToFirestore`), ein
  manipulierter Client könnte sich Premium eintragen. Lösung: RevenueCat-Webhook → Cloud
  Function schreibt `subscription`, Rules verbieten Clients das Feld. Braucht die Webhook-
  Einrichtung im RevenueCat-Dashboard.
- **Gemeinsames Gerät:** Im Kindermodus auf dem Elterngerät ist weiter das Elternkonto
  angemeldet, der PIN schützt dort nur die Oberfläche. Echte Trennung gibt es nur mit einem
  gekoppelten Gerät.
- **App Check für die Functions** (`enforceAppCheck`), sobald App Check überall aktiv ist.
- **Android-App-Link:** Auf Android öffnet der QR-Code die Web-App im Browser, nicht die
  installierte App. In der App geht der Code über „Ich bin ein Kind“.

## Phase 4: Schule ✅ (Branch `schule`, noch nicht deployt)

Datenmodell:

```
schools/{schoolId}                     Name
schools/{sid}/members/{uid}            role: admin | teacher  (schreiben nur Functions)
schools/{sid}/classes/{classId}        Name „5b“, Klassenstufe, Schulform
users/school_{sid}                     „Besitzer-Konto“ der Schüler, Lizenz (schoolLicenseUntil)
users/school_{sid}/children/{id}       Schüler, wie ChildModel + classId
studentCards/{sha256(token)}           QR-Karten (nur Hash, nur Functions)
schoolInvites/{code}                   Einladungen für Lehrkräfte (nur Functions)
```

Die Schüler liegen bewusst wie Kinder einer Familie unter `users/school_<id>/children`. Damit
laufen Quiz, Lexi, XP und Belohnungen für Schüler ohne jeden Umbau. Ein Schülergerät hat dieselben
Claims wie ein gekoppeltes Kindergerät.

Erledigt:

- **Schule anlegen:** Einstellungen → Schule → „Schule anlegen“. Wer anlegt, ist Schulleitung.
- **Lehrkräfte:** Die Schulleitung erzeugt einen Einladungscode (7 Tage, einmalig), die Lehrkraft
  gibt ihn unter Einstellungen → „Einer Schule beitreten“ ein. Alle Lehrkräfte sehen alle Klassen.
  Eine Lehrkraft bleibt für ihre eigene Familie ganz normal Elternteil. Die Schulleitung kann
  Lehrkräfte entfernen.
- **Klassen und Schüler:** Klasse mit Klassenstufe und Schulform anlegen, Schüler als Namensliste
  (ein Name pro Zeile) eintragen. Empfehlung in der App: Vorname + Anfangsbuchstabe.
- **QR-Karten:** Im Browser öffnet „Drucken“ eine A4-Seite mit 8 Karten pro Blatt. Das Kind scannt
  seine Karte mit der Tablet-Kamera und ist angemeldet. Karten sind wiederverwendbar (geteilte
  Tablets). „Neue Karte“ macht die alte ungültig.
- **Schul-Tablet:** Oben links „Abmelden“, damit das nächste Kind seine Karte scannen kann.
- **Schüler löschen:** komplett auf dem Server, inklusive Lexi-Gesprächen, Fotos, Karten und
  Gerätekonto.
- **Lizenz:** `schoolLicenseUntil` (Zeitstempel) am Dokument `users/school_<id>` gibt allen
  Schülern vollen Zugriff. Setzt nur Lerndex, z.B. in der Firebase Console.
- **Lexi-Chats bleiben privat:** Lehrkräfte sehen sie nicht (Rules). Freischalten ist eine
  Zeile in `firestore.rules` (`isPrivateForTeachers`), wenn die Schule es will und darf.
- **KI-Kosten:** Beim Anlegen einer Klasse werden keine KI-Fragen vorgeladen. Das passiert erst
  beim ersten Start auf dem Schülergerät, und nur für dieses Kind.
- **Tests:** 11 Schul-Tests im Emulator (insgesamt 41), Druckseite mit QR-Decoder geprüft,
  kompletter Ablauf im Browser gegen den Emulator durchgeklickt.

Offen:

- **Vor echten Schülerdaten:** Auftragsverarbeitungsvertrag (AVV) mit Schule bzw. Schulträger,
  Zustimmung des Datenschutzbeauftragten.
- **Import aus der Schulverwaltung:** Bisher Namen per Kopieren und Einfügen. Ein CSV-Import
  lohnt sich, wenn klar ist, welches Format die Schule exportiert.
- **Eltern ↔ Schule:** Sehen Eltern den Lernstand aus der Schule? Noch nicht verknüpft.
- **Lehrer-Ansicht am PC:** Die App ist im Browser auf Handybreite zentriert. Für den Lehrer-
  bereich wäre eine breitere Ansicht schöner.
- **Kartenwechsel ohne Abmelden:** Scannt ein Kind seine Karte, während noch ein anderes Kind
  angemeldet ist, meldet die App das erste ab. Im Emulator ließ sich das wegen der Neulade-
  Eigenheit (siehe Phase 3) nicht prüfen, nach dem Deploy testen.

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
