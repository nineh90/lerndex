// KI für die Web-App: Der Browser schickt seine Gemini-Anfrage hierher statt
// direkt an Firebase AI Logic. So steht im Browser kein nutzbarer Schlüssel,
// und es braucht weder App Check noch reCAPTCHA (siehe lib/src/ai/ai_model.dart).
//
// Schutz:
// - nur Kinder-/Schüler-/Lehrergeräte (Konten der Functions) und Eltern mit
//   bestätigter E-Mail und aktivem Abo bzw. Testzugang. Sonst könnte jeder
//   mit frisch angelegten Konten Gemini auf Kosten von Lerndex nutzen.
// - Tageslimit pro Konto (aiUsage/{uid}, nur Functions)
// - Modell, Region und Safety-Settings legt diese Function fest, nicht der
//   Client. Erlaubt sind nur Text und Bilder, Token-Limit gedeckelt.
//
// Inhalte (Kinderfragen, Fotos) werden nicht geloggt und nicht gespeichert.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const { getApp } = require("firebase-admin/app");
const { db } = require("./lib/firebase");
const { hasAccess } = require("./lib/access");

const { buildRequest, extractResult, MODEL, LOCATION, DAILY_LIMIT } = require("./lib/ai_request");

/** Wirft permission-denied, wenn das Konto die KI nicht nutzen darf. */
async function requireAiAccount(auth) {
  const token = auth.token;
  // Geräte- und Lehrerkonten legen nur die Functions an
  if (token.role === "student" || token.role === "teacher") return;
  // Lehrkräfte mit eigenem E-Mail-Konto (ältere Einladungen)
  if (token.schoolRole === "teacher" && token.schoolId) return;
  if (token.email_verified !== true) {
    throw new HttpsError("permission-denied", "Bitte bestätige zuerst deine E-Mail-Adresse.");
  }
  const user = await db.doc(`users/${auth.uid}`).get();
  if (!hasAccess(user.data())) {
    throw new HttpsError("permission-denied", "Lexi gibt es mit einem Lerndex-Abo.");
  }
}

/** Zählt den Aufruf; wirft resource-exhausted über dem Tageslimit. */
async function countUsage(uid) {
  const today = new Date().toISOString().slice(0, 10);
  const ref = db.doc(`aiUsage/${uid}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = snap.exists && snap.get("day") === today ? snap.get("count") || 0 : 0;
    if (count >= DAILY_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        "Für heute ist Lexis Denkpause erreicht. Morgen geht es weiter.",
      );
    }
    tx.set(ref, { day: today, count: count + 1, updatedAt: FieldValue.serverTimestamp() });
  });
}

async function callVertex(request) {
  const project = process.env.GCLOUD_PROJECT || getApp().options.projectId;
  const { access_token: token } = await getApp().options.credential.getAccessToken();
  const url = `https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${project}` +
    `/locations/${LOCATION}/publishers/google/models/${MODEL}:generateContent`;
  const res = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(request),
    signal: AbortSignal.timeout(110000),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    // Nur Status und Meldung loggen, nie den Inhalt der Anfrage
    console.error("Vertex AI", res.status, body.error?.status, body.error?.message);
    if (res.status === 429) {
      throw new HttpsError("resource-exhausted", "Lexi ist gerade sehr gefragt. Bitte gleich nochmal.");
    }
    if (res.status === 400) throw new HttpsError("invalid-argument", "Die KI konnte die Anfrage nicht verarbeiten.");
    throw new HttpsError("unavailable", "Die KI ist gerade nicht erreichbar.");
  }
  return body;
}

/**
 * Gemini-Anfrage der Web-App. Erwartet { contents, systemInstruction?,
 * generationConfig? } im Vertex-Format. Antwort { text, finishReason, … }.
 * Im Emulator antwortet ein Platzhalter (kein Zugriff auf Vertex AI).
 */
exports.aiGenerate = onCall(
  { timeoutSeconds: 120, memory: "512MiB", maxInstances: 20 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Bitte zuerst anmelden.");
    const vertexRequest = buildRequest(request.data);
    await requireAiAccount(request.auth);
    await countUsage(request.auth.uid);

    if (process.env.FUNCTIONS_EMULATOR === "true") {
      const last = vertexRequest.contents.at(-1).parts.find((p) => p.text)?.text || "";
      return { text: `Platzhalter: ${last}`, finishReason: "STOP", request: vertexRequest };
    }
    return extractResult(await callVertex(vertexRequest));
  },
);
