# Plan: Lerndex für Schulen und als Web-App

Begonnen: 27.10.2026. Zuletzt aktualisiert: 10.11.2026 (Release 1.2.1+18).

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

## Überblick (Stand 10.11.2026)

| Phase | Inhalt | Stand |
|---|---|---|
| 1 | Web-Version | ✅ live auf https://app.lerndex.de |
| 2 | Lexi liest vor | ✅ live |
| 3 | Rollen und Sicherheit | ✅ live |
| 4 + 4b | Schule, Lehrerkarten, Aufgaben, Statistik, Elternbriefe | ✅ live seit 03.11.2026 |
| – | Review: Sicherheit, DSGVO, Abo vom Server | ✅ live seit 10.11.2026 |
| 5 | Arbeitsverhalten, Stufen, Privilegien | ❌ nicht begonnen, wartet auf das Gespräch mit der Lehrerin |
| 6 | Laravel-Backend auf Hostinger | ❌ bewusst erst mit Schulvertrag |

### Was noch offen ist

Vor echten Schülerdaten (keine Programmierarbeit):
- Auftragsverarbeitungsvertrag (AVV) mit Schule bzw. Schulträger, Zustimmung der
  Datenschutzbeauftragten.

Technik:
- **App Check erzwingen** (Firebase Console, AI Logic und `enforceAppCheck` in den
  Functions), sobald die meisten Android-Nutzer auf 1.2.0+ sind. Firebase erzwingt es für
  AI Logic ohnehin ab 21.01.2027. Danach `LEGACY_PIN_MIRROR` in `functions/index.js` auf
  `false` (und die Übergangsregel in `firestore.rules` entfernen).
- **Bezahlen im Browser:** Paddle (Merchant of Record) über RevenueCat Web Billing, Nils
  legt das Konto an. Danach Import-Map in `web/index.html` anpassen und das Bezahlskript nur
  auf der Abo-Seite laden; Datenschutzerklärung ergänzen. Kein Android-Release nötig, die App
  erkennt das Abo über den Server-Abgleich.
- **Google-Login in Safari:** `authDomain` steht noch auf `lerndex-3775f.firebaseapp.com`.
  Safari kann den Login wegen fremder Cookies blockieren. Lösung: Login-Handler unter
  app.lerndex.de bereitstellen (`/__/auth/*` an Firebase durchreichen) und `authDomain`
  umstellen. Auf dem iPhone testen.
- **Fremde Server im Browser:** Firebase-JS-SDK (www.gstatic.com) und Google-Login-Skript
  (accounts.google.com/gsi/client), siehe Phase 1.
- **Altes Firebase Hosting** (`lerndex-3775f.web.app`) abschalten. Es liefert noch den Stand
  vom 04.11.2026; gedruckte Karten zeigen seit 1.2.1 fest auf app.lerndex.de.
- **Echte Geräte testen:** iPhone mit Safari, Schul-Tablet, PC (Kamera, Mikrofon, Vorlesen).
- **Händlerstatus in der Play Console** bis Februar 2027 (nur der Kontoinhaber, Nils).

Schulbereich:
- Schulkonto selbst löschen, Passwort ändern (bisher nur über Lerndex).
- Lehrkräfte können ihre PIN nicht selbst ändern (nur Reset über die Schulleitung).
- Import der Schülerliste als CSV, sobald das Exportformat der Schule bekannt ist.
- Breitere Ansicht für Lehrkräfte am PC (bisher Handybreite).
- Kartenwechsel ohne Abmelden auf geteilten Tablets live testen.

Entscheidungen:
- Wer sieht kritische Lexi-Gespräche von Schulkindern ohne verbundene Eltern? (Lehrkräfte sehen
  Lexi-Chats bisher nicht.)
- Sollen Aufgabenpakete nach einiger Zeit ablaufen?

Bekannte Grenze: Im Kindermodus auf dem Elterngerät ist das Elternkonto angemeldet, der PIN
schützt dort nur die Oberfläche. Echte Trennung nur mit gekoppeltem Kindergerät.

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

Ursprünglich offen (Stand 10.11.: siehe Markierungen):

1. *(Für die KI nicht mehr nötig: Im Browser läuft sie seit 1.2.0 über die Function
   `aiGenerate`.)* **reCAPTCHA Enterprise / App Check:** Firebase Console → App Check → Web-App registrieren →
   Site-Key als `RECAPTCHA_SITE_KEY` in `dart-defines.json` eintragen.
   Die **Erzwingung (Enforcement) erst einschalten, wenn auch Android App Check hat.**
   Sonst funktioniert die KI in der Play-Store-App nicht mehr.
2. *(Teilweise erledigt: app.lerndex.de läuft auf Hostinger. Offen bleibt `authDomain`, siehe
   Überblick.)* **Domain:** z.B. `app.lerndex.de` in Firebase Hosting anbinden und unter
   Authentication → Einstellungen → Autorisierte Domains eintragen.
   `authDomain` in `firebase_options.dart` (web) auf diese Domain setzen. Sonst kann der
   Google-Login in Safari scheitern, weil Safari Cookies fremder Domains blockiert.
3. *(Offen, jetzt mit Paddle statt Stripe geplant, siehe Überblick.)* **RevenueCat Web
   Billing:** Stripe verbinden, Web-Produkte anlegen, Web-API-Key als
   `REVENUECAT_WEB_KEY` eintragen. Für die Schule nicht nötig, dort per Rechnung.
   Dann zusätzlich die Import-Map in `web/index.html` entfernen (sonst bleibt RevenueCat im
   Browser abgeschaltet) und vorher klären, ob dafür ein Cookie-/Einwilligungsbanner nötig
   ist: Stripe.js lädt Telemetrie von Stripe-Servern.
4. *(Ersetzt durch `tool/deploy/web_hostinger.sh`.)* **Deploy:**
   `rm -rf .dart_tool/flutter_build build/web`, dann
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

## Stand Deploy (02.11.2026)

- Functions (15, neu: `leaveChildDevice`) deployt, öffentlich aufrufbar über „ohne IAM-Prüfung“
  (`invokerIamDisabled`, die Firmenrichtlinie verbietet `allUsers`). Bestehende Functions behalten
  die Einstellung beim Deploy. Bei einer **neuen** Function meldet `npm run deploy`, es könne den
  Invoker nicht setzen. Dann den Cloud-Run-Dienst selbst umstellen (Kevins Konto darf das):
  Dienst über die Cloud-Run-API v2 holen, `template.revision` entfernen,
  `invokerIamDisabled: true` setzen und per PATCH zurückschicken. Danach muss ein Aufruf ohne
  Anmeldung mit „Bitte zuerst anmelden.“ (401) antworten, nicht mit einem 403 von Google.
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
  - `leaveChildDevice` (seit 02.11.2026): Ein Kindergerät meldet sich mit dem Eltern-PIN
    selbst ab (Abmelde-Knopf oben links im Kinder-Dashboard). Prüft den PIN auf dem Server (gleiche
    Sperre wie im Elternbereich) und trägt nur dieses Gerät aus der Geräteliste aus. Andere
    Geräte des Kindes bleiben gekoppelt. Ohne festgelegten PIN geht es nicht, dann bleibt
    „Alle abmelden“ im Elternbereich.
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

### Offen (Stand 10.11.2026)

- ✅ *Erledigt 10.11.2026 (syncSubscription, revenuecatWebhook).* **Abo serverseitig:** Den
  Abo-Status schrieb die App (`_syncToFirestore`), ein
  manipulierter Client könnte sich Premium eintragen. Lösung: RevenueCat-Webhook → Cloud
  Function schreibt `subscription`, Rules verbieten Clients das Feld. Braucht die Webhook-
  Einrichtung im RevenueCat-Dashboard.
- **Gemeinsames Gerät:** Im Kindermodus auf dem Elterngerät ist weiter das Elternkonto
  angemeldet, der PIN schützt dort nur die Oberfläche. Echte Trennung gibt es nur mit einem
  gekoppelten Gerät.
- **App Check für die Functions** (`enforceAppCheck`), sobald App Check überall aktiv ist.
- ✅ *Erledigt in 1.2.0 (App Links, QR-Scanner).* **Android-App-Link:** Auf Android öffnete der QR-Code die Web-App im Browser, nicht die
  installierte App. In der App geht der Code über „Ich bin ein Kind“.

## Phase 4: Schule ✅ (live seit 03.11.2026)

Datenmodell:

```
schools/{schoolId}                     Name
schools/{sid}/members/{uid}            role: admin | teacher  (schreiben nur Functions)
schools/{sid}/classes/{classId}        Name „5b“, Klassenstufe, Schulform
users/school_{sid}                     „Besitzer-Konto“ der Schüler, Lizenz (schoolLicenseUntil)
users/school_{sid}/children/{id}       Schüler, wie ChildModel + classId
studentCards/{sha256(token)}           QR-Karten (nur Hash, nur Functions)
schoolInvites/{code}                   Einladungen für Lehrkräfte (nur Functions)
schoolSignups/{code}                   Einladungen für neue Schulen, von Lerndex (nur Functions)
users/{uid}.accountType = "school"     reines Schulkonto (nur Schulbereich)
```

Die Schüler liegen bewusst wie Kinder einer Familie unter `users/school_<id>/children`. Damit
laufen Quiz, Lexi, XP und Belohnungen für Schüler ohne jeden Umbau. Ein Schülergerät hat dieselben
Claims wie ein gekoppeltes Kindergerät.

Erledigt:

- **Schule anlegen (seit 02.11.2026 nur mit Einladung von Lerndex):**
  `python3 tool/admin/schule.py einladen [--name "…"] [--bis 2027-07-31]` erzeugt einen
  Einmal-Link `…/schule/CODE` (30 Tage gültig). Die Schulleitung registriert darüber Schule und
  Konto, die Lizenz kommt aus der Einladung. `schule.py liste` zeigt Schulen und offene
  Einladungen, `schule.py lizenz SCHUL_ID DATUM` verlängert.
- **Reine Schulkonten:** Konten, die über einen Schul- oder Lehrerlink neu entstehen, haben
  `accountType: "school"`. Nach dem Anmelden sehen sie nur den Schulbereich (Klassen,
  Lehrkräfte, Abmelden), keinen Elternbereich, keine PIN, kein Abo.
- **Lehrkräfte:** Die Schulleitung schickt einen Link `…/lehrer/CODE` (7 Tage, einmalig). Die
  Lehrkraft legt darüber ein Schulkonto an oder tritt mit ihrem Elternkonto bei (dann behält sie
  ihren Elternbereich und erreicht die Schule über das Schul-Symbol). Alle Lehrkräfte sehen alle
  Klassen. Die Schulleitung kann Lehrkräfte entfernen.
- **Offen:** Konto löschen für reine Schulkonten (bisher nur über uns), Passwort ändern im
  Schulbereich.
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
- ✅ *Erledigt in Phase 4b (Elternbrief).* **Eltern ↔ Schule:** Sehen Eltern den Lernstand
  aus der Schule?
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

## Phase 4b: Lehrkräfte per Karte, Aufgaben, Statistik, Eltern ✅ (live seit 03.11.2026)

Entscheidungen mit Kevin (02.11.2026): Lehrer-Anmeldung per QR-Karte + PIN; die Schulleitung
verwaltet nur Lehrkräfte und sieht keine Schülerdaten; Elternanbindung kostet nichts (Schul-
lizenz), eigene Kinder brauchen weiter ein Abo; Eltern sehen auch Lexi-Gespräche aus der
Schulzeit; Fortschritt aus einem Familienkonto wird nicht übernommen.

- **Lehrkräfte:** `createTeacher`, `reissueTeacherCard` (optional PIN zurücksetzen),
  `redeemTeacherCard` (PIN festlegen bzw. prüfen, Sperre 15 Min. nach 5 Fehlversuchen),
  `removeTeacher` (Kartenlehrkraft: Konto, Karten, PIN weg). Druckvorlage mit Anleitung.
  Einladungslinks und Beitritt per Code für Lehrkräfte gibt es nicht mehr.
- **Statistik:** Klassenübersicht (aktiv diese Woche, Lernzeit pro Kind, Quizze) und pro Kind
  die Statistikseite der Eltern ohne Lexi und Familienbelohnungen.
- **Aufgaben:** Thema eintippen oder Foto (Arbeitsblatt, Tafelbild). Prompt-Modus
  `teacherTopic`: Thema verbindlich für alle Fragen. Lehrkraft prüft, wählt Kinder, jedes Kind
  bekommt ein freigegebenes Paket in `generated_batches` (`assignmentId`, `classId`).
  Zurückziehen löscht alle Pakete des Auftrags.
- **Elternbrief:** eine Seite pro Kind mit „Eltern verbinden“ (`…/e/CODE`) und „Zu Hause
  lernen“ (Heimkarte, bleibt beim Neudruck der Schulkarten gültig). Ohne Anmeldung merkt sich
  die App den Code und löst ihn nach Anmeldung/Registrierung im Familien-Dashboard ein.
  Eltern ohne Abo, aber mit Schulkind, landen nicht auf der Abo-Seite.
- **Tests:** 51 Emulator-Tests, 283 Flutter-Tests; Schulleitung → Lehrkraft → Klasse →
  Statistik → Aufgaben und Elternbrief → Eltern-Dashboard im Emulator durchgeklickt.
- **Deployt am 03.11.2026:** 19 Functions (6 neue per `invokerIamDisabled` freigeschaltet,
  createTeacherInvite und joinSchool gelöscht), Firestore- und Storage-Regeln (jetzt per CLI,
  `firebase deploy --only firestore:rules,storage`), Web-App. Vorherige Regeln:
  `docs/rules-backup/*.live-2026-11-03.*` (Rulesets b8a5382f / 2b757466, zurück über den
  Verlauf in der Console).
- **Offen:** ~~Elternbrief fürs Kinderhandy in der Android-App~~ (erledigt in 1.2.1: Dialog
  mit Eltern-Code und Heim-Link je Kind), Kartenlehrkräfte können ihre PIN nicht selbst ändern (nur Reset über die Leitung).

## Review 05.11.2026: Sicherheit, DSGVO, Abo

Funde und Stand: siehe Commits ab 424e25a. Live seit 05.11.: Kinderschutz-Regeln
(Mail-Relay zu, Kindergerät darf Profil und Belohnungen nicht frei ändern).

**Neue Functions** (`functions/subscription.js`, `functions/cleanup.js`):
- `syncSubscription` (App ruft nach Kauf/Start auf) und `revenuecatWebhook`: Der
  Server holt den Abo-Status bei RevenueCat und schreibt `users/{uid}.subscription`
  (inkl. `extraChildSlots` = Käufe von `lerndex_extra_child_slot`). Die App schreibt
  das Feld nicht mehr.
- `deleteRevenueCatCustomer`: löscht den Kunden bei RevenueCat, wenn ein Elternkonto
  gelöscht wird.
- `cleanupOldTutorChats`: täglich 03:30, löscht Lexi-Gespräche (`startedAt` älter
  als 14 Tage), alte `active_tutor_chat`-Reste und Fotos in `tutor_worksheets/`.
- `aiGenerate` nur noch für Geräte-/Lehrerkonten und Eltern mit bestätigter
  E-Mail und Abo (oder Testzugang, Schullizenz); Denkstufe höchstens LOW.

**Reihenfolge beim Deploy:**
1. Secrets anlegen (Kevin):
   `firebase functions:secrets:set REVENUECAT_SECRET_KEY` (RevenueCat → API Keys →
   Secret API Key, v1) und `firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH`
   (langer Zufallswert, z. B. `openssl rand -hex 32`).
2. `firebase deploy --only firestore:indexes` (Index `tutor_sessions.startedAt` als
   Collection-Group; die übrigen Indizes stehen unverändert in `firestore.indexes.json`).
3. `cd functions && npm run deploy`. Die vier neuen Functions danach per
   `invokerIamDisabled` freischalten (wie unter „Stand Deploy 02.11.“ beschrieben);
   `cleanupOldTutorChats` ist ein Zeitplan und braucht das nicht.
4. RevenueCat → Integrations → Webhooks: URL von `revenuecatWebhook`
   (europe-west3), Authorization-Header = Wert von `REVENUECAT_WEBHOOK_AUTH`.
   Einmal „Send test event“ (Antwort 200).
5. Bestehende Abos einmal abgleichen: `python3 tool/admin/abo_abgleich.py --los`
   (schickt für jedes Konto mit `subscription`-Feld ein Ereignis an den Webhook).
6. Regeln (`firestore.rules`, `storage.rules`) deployen: sperrt `subscription` für
   Clients. Ältere App-Versionen, die das Feld noch selbst schreiben, scheitern
   damit leise (Fehler wird abgefangen); der Kauf eines Zusatzplatzes zeigt dort
   eine Fehlermeldung, obwohl er geklappt hat – der Server zählt ihn trotzdem.
7. nginx: `tool/deploy/web_hostinger.sh --setup` (HSTS, Einbett-Schutz, keine
   Versionsnummer).

**Deployt am 10.11.2026:** Secrets (Kevin hat dafür die Rollen Secret Manager- und Cloud
Scheduler-Administrator bekommen), Index, alle Functions (syncSubscription,
revenuecatWebhook, previewSchoolChild per `invokerIamDisabled` freigeschaltet;
cleanupOldTutorChats täglich 03:30), RevenueCat-Webhook (Test-Ereignis 200), Abgleich der
70 Konten (keine Familie verliert Zugang, 2 bezahlte Solo-Abos waren fälschlich inaktiv),
Firestore- und Storage-Regeln (Sicherung `docs/rules-backup/*.live-2026-11-10.*`), nginx
(HSTS, frame-ancestors, server_tokens off; nach `--setup` ist `nginx -s reload` nötig).
Offen: KI-Live-Check, dann Release (AAB + Web).
