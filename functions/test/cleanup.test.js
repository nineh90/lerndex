// Aufbewahrung: Lexi-Gespräche nach 14 Tagen löschen (functions/cleanup.js).
const test = require("node:test");
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test("Aufbewahrungs-Tests brauchen den Emulator (npm run test:emulator)", { skip: true });
  return;
}

const { adb, Timestamp, PROJECT } = require("./_client");
const { getStorage } = require("firebase-admin/storage");
const { runRetention } = require("../cleanup");

const DAY = 24 * 60 * 60 * 1000;

test("Aufbewahrung: alte Gespräche, alte Chat-Ablage und alte Fotos weg, neue bleiben", async () => {
  const base = "users/rp1/children/c1";
  const now = new Date();
  await adb.doc(`${base}/tutor_sessions/alt`).set({ startedAt: Timestamp.fromMillis(now - 15 * DAY) });
  await adb.doc(`${base}/tutor_sessions/alt/messages/m1`).set({ text: "alt" });
  await adb.doc(`${base}/tutor_sessions/neu`).set({ startedAt: Timestamp.fromMillis(now - 2 * DAY) });
  await adb.doc(`${base}/tutor_sessions/neu/messages/m1`).set({ text: "neu" });
  await adb.doc("users/school_x/children/s1/tutor_sessions/alt").set({ startedAt: Timestamp.fromMillis(now - 30 * DAY) });
  await adb.doc(`${base}/active_tutor_chat/a1`).set({ timestamp: Timestamp.fromMillis(now - 20 * DAY) });
  await adb.doc(`${base}/active_tutor_chat/a2`).set({ timestamp: Timestamp.fromMillis(now - DAY) });

  const bucket = getStorage().bucket(`${PROJECT}.appspot.com`);
  await bucket.file("tutor_worksheets/rp1/c1/1.jpg").save(Buffer.from([1, 2, 3]));

  // Heute: Foto ist frisch und bleibt
  let counts = await runRetention(now, bucket);
  assert.equal(counts.files, 0);
  assert.equal((await adb.doc(`${base}/tutor_sessions/alt`).get()).exists, false);
  assert.equal((await adb.doc(`${base}/tutor_sessions/alt/messages/m1`).get()).exists, false);
  assert.equal((await adb.doc("users/school_x/children/s1/tutor_sessions/alt").get()).exists, false);
  assert.equal((await adb.doc(`${base}/tutor_sessions/neu/messages/m1`).get()).exists, true);
  assert.equal((await adb.doc(`${base}/active_tutor_chat/a1`).get()).exists, false);
  assert.equal((await adb.doc(`${base}/active_tutor_chat/a2`).get()).exists, true);
  assert.equal((await bucket.file("tutor_worksheets/rp1/c1/1.jpg").exists())[0], true);

  // In 15 Tagen: Foto ist zu alt
  counts = await runRetention(new Date(now.getTime() + 15 * DAY), bucket);
  assert.ok(counts.files >= 1);
  assert.equal((await bucket.file("tutor_worksheets/rp1/c1/1.jpg").exists())[0], false);
});
