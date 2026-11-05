// Aufbewahrung: Lexi-Gespräche und Fotos von Aufgabenblättern werden nach
// 14 Tagen gelöscht – für Familien und Schulen gleich.
//
// Vorher sollte das die App erledigen (runAutoCleanupIfNeeded), wurde aber nie
// aufgerufen; bei Schulkindern hätte es ohnehin niemand anstoßen können.
// Braucht den Index tutor_sessions.startedAt (Collection-Group, firestore.indexes.json).

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { db } = require("./lib/firebase");

const RETENTION_DAYS = 14;
const PAGE = 200;

/** Löscht alles, was älter als die Aufbewahrungsfrist ist. Gibt Zähler zurück. */
async function runRetention(now = new Date(), bucket = getStorage().bucket()) {
  const cutoff = new Date(now.getTime() - RETENTION_DAYS * 24 * 60 * 60 * 1000);
  const counts = { sessions: 0, activeChats: 0, files: 0 };

  // 1. Gespräche samt Nachrichten
  for (;;) {
    const old = await db
      .collectionGroup("tutor_sessions")
      .where("startedAt", "<", Timestamp.fromDate(cutoff))
      .limit(PAGE)
      .get();
    if (old.empty) break;
    for (const session of old.docs) {
      await db.recursiveDelete(session.ref);
      counts.sessions++;
    }
    if (old.size < PAGE) break;
  }

  // 2. Alte Ablage des laufenden Chats (wird von der App nicht mehr
  //    geschrieben, kann aber noch Inhalte älterer Versionen enthalten)
  let last = null;
  for (;;) {
    let q = db.collectionGroup("active_tutor_chat").orderBy("__name__").limit(PAGE);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.empty) break;
    const batch = db.batch();
    let n = 0;
    for (const doc of page.docs) {
      const ts = doc.get("timestamp");
      const when = ts?.toDate?.() ?? doc.updateTime?.toDate?.() ?? null;
      if (!when || when < cutoff) {
        batch.delete(doc.ref);
        n++;
      }
    }
    if (n > 0) await batch.commit();
    counts.activeChats += n;
    last = page.docs[page.docs.length - 1];
    if (page.size < PAGE) break;
  }

  // 3. Fotos von Aufgabenblättern (tutor_worksheets/<konto>/<kind>/…)
  let query = { prefix: "tutor_worksheets/", maxResults: 500, autoPaginate: false };
  for (;;) {
    const [files, next] = await bucket.getFiles(query);
    for (const file of files) {
      const created = new Date(file.metadata.timeCreated);
      if (created < cutoff) {
        await file.delete({ ignoreNotFound: true });
        counts.files++;
      }
    }
    if (!next) break;
    query = next;
  }
  return counts;
}

exports.cleanupOldTutorChats = onSchedule(
  { schedule: "every day 03:30", timeZone: "Europe/Berlin", timeoutSeconds: 540, memory: "512MiB" },
  async () => {
    const counts = await runRetention();
    console.log("Aufbewahrung", counts);
  },
);

module.exports.runRetention = runRetention;
module.exports.RETENTION_DAYS = RETENTION_DAYS;
