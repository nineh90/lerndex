# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Entwicklung starten

```bash
flutter run --dart-define-from-file=dart_defines.json
```

`dart-defines.json` enthält die RevenueCat API-Keys und liegt in `.gitignore`. Ohne dieses Flag schlägt der App-Start fehl (leere API-Keys → RevenueCat-Fehler).

## Code-Generierung

Riverpod-Provider, Freezed-Modelle und JSON-Serialisierung werden generiert:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

Generierte Dateien enden auf `.g.dart` oder `.freezed.dart` — nie manuell bearbeiten.

## Build & Release

CI/CD läuft über Codemagic (`codemagic.yaml`). Lokaler Release-Build:

```bash
flutter build apk --dart-define-from-file=dart_defines.json
flutter build ipa --dart-define-from-file=dart_defines.json
```

## Architektur

### Feature-Struktur

`lib/src/features/` ist nach Features gegliedert, jedes Feature folgt dem Muster `data/` → `domain/` → `presentation/`.

| Feature | Beschreibung |
|---|---|
| `auth/` | Firebase Auth (E-Mail + Google), Eltern-Account, Kinder-Profile |
| `quiz/` | Quiz-Engine (State Machine), Fragen aus JSON + KI |
| `generated_tasks/` | Eltern fotografieren Hausaufgaben, KI generiert passende Aufgaben |
| `tutor/` | KI-Tutor "Lexi" – Chat-Interface für Kinder |
| `student_dashboard/` | Schüler-Ansicht, aufgeteilt in Early Learner (Kl. 1–2) und Standard (Kl. 3+) |
| `parent_dashboard/` | Eltern-Ansicht mit PIN-Schutz, Statistiken, Belohnungsverwaltung |
| `rewards/` | XP-System (50 Level), Sterne, Belohnungen, Achievements |
| `subscription/` | RevenueCat IAP – Pläne: Starter, Single, Family |
| `stt/` + `tts/` | Speech-to-Text und Text-to-Speech für Tutor |
| `learning_time/` | Lernzeit-Tracking pro Kind |

### State Management

Riverpod mit Code-Generierung via `@riverpod`-Annotation. Provider-Dateien enden auf `_provider.dart` oder `_repository.dart`. Die generierten Teile sind in `.g.dart`.

### KI-Zugang (wichtig)

**Alle KI-Aufrufe laufen ausschließlich über `lib/src/ai/vertex_ai_service.dart`.** Kein direktes `google_generative_ai` — ausschließlich `firebase_ai` mit `FirebaseAI.vertexAI()`. Grund: DSGVO-Konformität für Kinderdaten via Google Cloud (Vertex AI).

`VertexAIService` hat drei Zuständigkeiten:
1. `sendTutorMessage()` — Tutor-Chat (pro Kind gecachtes Modell)
2. `generateTasksFromImage()` — Aufgaben aus Foto generieren (für Eltern)
3. `generateQuizQuestions()` — Quiz-Fragen dynamisch generieren

### Quiz-System

`QuizEngine` (`lib/src/features/quiz/presentation/quiz_engine.dart`) ist eine State Machine mit `QuizPhase`-Enum. Fragen kommen aus zwei Quellen:
- Statische JSON-Dateien in `assets/questions/` (pro Fach eine Datei)
- Dynamisch generiert via Vertex AI (`ExtendedQuizRepository`)

### Fächerstruktur nach Klassenstufe

- Klasse 1–2: „Early Learner"-Modus (Zahlen, Buchstaben, Farben/Formen)
- Klasse 3–4: Mathe, Deutsch, Englisch, Sachkunde
- Klasse 5–10: Mathe, Deutsch, Englisch, Biologie, Chemie, Physik, Geschichte

### Datenmodell (Firestore)

- `users/{uid}` — Eltern-Account (Subscription-Status, Kinder-Limit)
- `users/{uid}/children/{childId}` — Kinder-Profile (`ChildModel`)
- Kinder-Limit hängt vom Abo-Plan ab (Starter: 1, Single: 1, Family: 3 + käufliche Slots)

### Tutor-Sicherheit

Der Tutor-System-Prompt erzwingt die Sokrates-Methode: niemals direkte Lösungen, sondern geleitetes Denken. Der KI-Response enthält versteckte Tags `[FACH:...]` und `[KORREKT:ja/nein]`, die in `_stripSubjectTag()` vor der Anzeige entfernt werden und intern für XP-Vergabe und Statistiken genutzt werden.
