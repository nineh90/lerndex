// Einmal-Codes (Kopplung, Lehrer-Einladung) sicher einlösen.
//
// Der Code wird in einer Transaktion für kurze Zeit reserviert und erst
// gelöscht, wenn alles geklappt hat. Scheitert danach etwas (z.B. fehlende
// Rechte beim Anlegen des Kontos), wird die Reservierung zurückgenommen und
// der Code bleibt gültig. Vorher wurde er sofort gelöscht – ein zweiter
// Versuch meldete dann „Code falsch“.

const { FieldValue } = require("firebase-admin/firestore");
const { db } = require("./firebase");

const CLAIM_MS = 60 * 1000;

/**
 * Reserviert den Code und führt [work] aus. Gibt null zurück, wenn der Code
 * fehlt, abgelaufen oder gerade von einem anderen Gerät reserviert ist.
 */
async function redeemOnce(ref, work) {
  const data = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    const d = snap.data();
    if (d.expiresAt.toMillis() < Date.now()) {
      tx.delete(ref);
      return null;
    }
    const claimedAt = d.claimedAt?.toMillis?.() ?? 0;
    if (Date.now() - claimedAt < CLAIM_MS) return null;
    tx.update(ref, { claimedAt: FieldValue.serverTimestamp() });
    return d;
  });
  if (!data) return null;

  try {
    const result = await work(data);
    if (result == null) {
      // Ungültig (z.B. Kind gelöscht): nichts verbrauchen
      await ref.update({ claimedAt: FieldValue.delete() });
      return null;
    }
    await ref.delete();
    return result;
  } catch (e) {
    await ref.update({ claimedAt: FieldValue.delete() }).catch(() => {});
    throw e;
  }
}

module.exports = { redeemOnce, CLAIM_MS };
