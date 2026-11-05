// Benachrichtigungen an Lerndex per E-Mail.
//
// Läuft über dieselbe Firebase-Erweiterung „Trigger Email“ wie das Feedback
// aus der App: Ein Dokument in mail/ mit `to` und `message` wird verschickt,
// das Ergebnis steht danach unter `delivery` im Dokument.

const { FieldValue } = require("firebase-admin/firestore");
const { db } = require("./firebase");

const LERNDEX_ADDRESS = "support@lerndex.de";

/**
 * Mail an Lerndex. Wirft nie: Eine fehlende Benachrichtigung darf die
 * eigentliche Aktion (z.B. Schule anlegen) nicht scheitern lassen.
 */
async function notifyLerndex(subject, text, meta = {}) {
  try {
    await db.collection("mail").add({
      to: [LERNDEX_ADDRESS],
      message: { subject, text },
      source: "functions",
      ...meta,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error("Benachrichtigung an Lerndex fehlgeschlagen:", e);
  }
}

module.exports = { notifyLerndex, LERNDEX_ADDRESS };
