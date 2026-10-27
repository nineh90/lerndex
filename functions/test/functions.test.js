// Cloud Functions im Emulator. Starten mit: npm run test:emulator
const test = require("node:test");
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test("Function-Tests brauchen den Emulator (npm run test:emulator)", { skip: true });
  return;
}

const fs = require("node:fs");
const path = require("node:path");
const { initializeApp, deleteApp } = require("firebase/app");
const {
  getAuth, connectAuthEmulator, createUserWithEmailAndPassword,
  signInWithCustomToken, signOut,
} = require("firebase/auth");
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require("firebase/functions");
const {
  getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc,
} = require("firebase/firestore");
const admin = require("firebase-admin/app");
const { getFirestore: adminFirestore, Timestamp } = require("firebase-admin/firestore");
const { getAuth: adminAuth } = require("firebase-admin/auth");
const { hashPin, legacyHashPin } = require("../lib/helpers");

const PROJECT = "demo-lerndex";
const emulators = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "..", "firebase.json"), "utf8"),
).emulators;

admin.initializeApp({ projectId: PROJECT });
const adb = adminFirestore();

let appCount = 0;
const apps = [];

/** Eigene Client-App (= eigenes Gerät) gegen die Emulatoren. */
function device() {
  const app = initializeApp({ projectId: PROJECT, apiKey: "demo" }, `d${appCount++}`);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://127.0.0.1:${emulators.auth.port}`, { disableWarnings: true });
  const functions = getFunctions(app, "europe-west3");
  connectFunctionsEmulator(functions, "127.0.0.1", emulators.functions.port);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, "127.0.0.1", emulators.firestore.port);
  const call = async (name, data) => (await httpsCallable(functions, name)(data)).data;
  return { app, auth, db, call };
}

/** Elternteil mit zwei Kindern anlegen und anmelden. */
async function parentWithChildren() {
  const d = device();
  const email = `p${Date.now()}${Math.random().toString(36).slice(2, 6)}@test.de`;
  const { user } = await createUserWithEmailAndPassword(d.auth, email, "geheim123");
  await setDoc(doc(d.db, `users/${user.uid}`), { plan: "family" });
  await setDoc(doc(d.db, `users/${user.uid}/children/jan`), { name: "Jan" });
  await setDoc(doc(d.db, `users/${user.uid}/children/max`), { name: "Max" });
  return { ...d, uid: user.uid };
}

async function expectError(promise, code) {
  await assert.rejects(promise, (e) => {
    assert.equal(e.code, `functions/${code}`, e.message);
    return true;
  });
}

test.after(async () => {
  for (const app of apps) await deleteApp(app);
});

// ── Kindergeräte koppeln ─────────────────────────────────────────────────────

test("Koppeln: Code erzeugen, einlösen, als Kind angemeldet", async () => {
  const parent = await parentWithChildren();
  const { code, expiresAt } = await parent.call("createPairingCode", { childId: "jan" });
  assert.match(code, /^[A-HJ-NP-Z2-9]{8}$/);
  assert.ok(new Date(expiresAt) > new Date());

  const kid = device();
  // Kleinbuchstaben und Bindestrich, wie ein Kind es abtippt
  const typed = `${code.slice(0, 4)}-${code.slice(4)}`.toLowerCase();
  const { token, childName } = await kid.call("redeemPairingCode", { code: typed });
  assert.equal(childName, "Jan");

  const { user } = await signInWithCustomToken(kid.auth, token);
  assert.equal(user.uid, `kid:${parent.uid}:jan`);
  const { claims } = await user.getIdTokenResult();
  assert.equal(claims.role, "student");
  assert.equal(claims.parentUid, parent.uid);
  assert.equal(claims.childId, "jan");

  // Mit den Rules: eigenes Kind ja, Geschwister nein
  assert.equal((await getDoc(doc(kid.db, `users/${parent.uid}/children/jan`))).get("name"), "Jan");
  await assert.rejects(getDoc(doc(kid.db, `users/${parent.uid}/children/max`)));

  // Eltern sehen das Gerät
  const devices = await adb.collection(`users/${parent.uid}/children/jan/devices`).get();
  assert.equal(devices.size, 1);
});

test("Koppeln: Code nur einmal gültig", async () => {
  const parent = await parentWithChildren();
  const { code } = await parent.call("createPairingCode", { childId: "jan" });
  await device().call("redeemPairingCode", { code });
  await expectError(device().call("redeemPairingCode", { code }), "not-found");
});

test("Koppeln: neuer Code macht den alten ungültig", async () => {
  const parent = await parentWithChildren();
  const first = await parent.call("createPairingCode", { childId: "jan" });
  const second = await parent.call("createPairingCode", { childId: "jan" });
  await expectError(device().call("redeemPairingCode", { code: first.code }), "not-found");
  await device().call("redeemPairingCode", { code: second.code });
});

test("Koppeln: abgelaufener und unsinniger Code", async () => {
  const parent = await parentWithChildren();
  await adb.doc("pairingCodes/ABCDEFGH").set({
    parentUid: parent.uid, childId: "jan",
    expiresAt: Timestamp.fromMillis(Date.now() - 1000),
  });
  await expectError(device().call("redeemPairingCode", { code: "ABCDEFGH" }), "not-found");
  assert.equal((await adb.doc("pairingCodes/ABCDEFGH").get()).exists, false);
  await expectError(device().call("redeemPairingCode", { code: "x" }), "not-found");
  await expectError(device().call("redeemPairingCode", {}), "not-found");
});

test("Koppeln: nur Eltern, nur eigene Kinder", async () => {
  const parent = await parentWithChildren();
  await expectError(device().call("createPairingCode", { childId: "jan" }), "unauthenticated");
  await expectError(parent.call("createPairingCode", { childId: "gibtsnicht" }), "not-found");
  await expectError(parent.call("createPairingCode", {}), "invalid-argument");

  // Ein Kindergerät darf keine Codes erzeugen
  const { code } = await parent.call("createPairingCode", { childId: "jan" });
  const kid = device();
  const { token } = await kid.call("redeemPairingCode", { code });
  await signInWithCustomToken(kid.auth, token);
  await expectError(kid.call("createPairingCode", { childId: "max" }), "permission-denied");
  await expectError(kid.call("unpairChildDevices", { childId: "jan" }), "permission-denied");
});

test("Abmelden: Konto gesperrt, Geräte weg, neu koppeln geht", async () => {
  const parent = await parentWithChildren();
  const { code } = await parent.call("createPairingCode", { childId: "jan" });
  await device().call("redeemPairingCode", { code });

  const { unpaired } = await parent.call("unpairChildDevices", { childId: "jan" });
  assert.equal(unpaired, 1);
  const kidUser = await adminAuth().getUser(`kid:${parent.uid}:jan`);
  assert.equal(kidUser.disabled, true);
  assert.equal((await adb.collection(`users/${parent.uid}/children/jan/devices`).get()).size, 0);

  // Ohne gekoppeltes Gerät: kein Fehler
  assert.equal((await parent.call("unpairChildDevices", { childId: "max" })).unpaired, 0);

  const again = await parent.call("createPairingCode", { childId: "jan" });
  await device().call("redeemPairingCode", { code: again.code });
  assert.equal((await adminAuth().getUser(`kid:${parent.uid}:jan`)).disabled, false);
});

// ── Eltern-PIN ───────────────────────────────────────────────────────────────

test("PIN: setzen, prüfen, nicht im users-Dokument", async () => {
  const parent = await parentWithChildren();
  await parent.call("setParentPin", { pin: "4711" });

  const user = (await adb.doc(`users/${parent.uid}`).get()).data();
  assert.equal(user.pinSet, true);
  assert.equal(user.hashedPin, undefined);
  assert.ok((await adb.doc(`users/${parent.uid}/private/pin`).get()).exists);

  assert.deepEqual(await parent.call("verifyParentPin", { pin: "4711" }), { ok: true });
  assert.deepEqual(await parent.call("verifyParentPin", { pin: "1234" }), { ok: false });
  assert.deepEqual(await parent.call("verifyParentPin", { pin: "abc" }), { ok: false });
});

test("PIN: ändern nur mit richtigem altem PIN", async () => {
  const parent = await parentWithChildren();
  await parent.call("setParentPin", { pin: "4711" });
  await expectError(parent.call("setParentPin", { pin: "1111", oldPin: "0000" }), "permission-denied");
  await parent.call("setParentPin", { pin: "1111", oldPin: "4711" });
  assert.deepEqual(await parent.call("verifyParentPin", { pin: "1111" }), { ok: true });
  await expectError(parent.call("setParentPin", { pin: "12" }), "invalid-argument");
});

test("PIN: nach 5 Fehlversuchen gesperrt", async () => {
  const parent = await parentWithChildren();
  await parent.call("setParentPin", { pin: "4711" });
  for (let i = 0; i < 5; i++) {
    assert.deepEqual(await parent.call("verifyParentPin", { pin: "0000" }), { ok: false });
  }
  await assert.rejects(parent.call("verifyParentPin", { pin: "4711" }), (e) => {
    assert.equal(e.code, "functions/resource-exhausted");
    assert.ok(e.details.retryAfterSeconds > 0);
    return true;
  });
});

test("PIN: alter Hash aus dem users-Dokument wird umgezogen", async () => {
  const parent = await parentWithChildren();
  const salt = "c2FsdC1zYWx0LXNhbHQ=";
  await adb.doc(`users/${parent.uid}`).set(
    { hashedPin: hashPin("2468", salt), pinSalt: salt, pinFailedAttempts: 2 },
    { merge: true },
  );
  assert.deepEqual(await parent.call("verifyParentPin", { pin: "2468" }), { ok: true });

  const user = (await adb.doc(`users/${parent.uid}`).get()).data();
  assert.equal(user.hashedPin, undefined);
  assert.equal(user.pinSalt, undefined);
  assert.equal(user.pinSet, true);
  assert.deepEqual(await parent.call("verifyParentPin", { pin: "2468" }), { ok: true });
});

test("PIN: ganz alter Hash ohne Salt wird umgezogen", async () => {
  const parent = await parentWithChildren();
  await adb.doc(`users/${parent.uid}`).set({ hashedPin: legacyHashPin("1357") }, { merge: true });
  assert.deepEqual(await parent.call("verifyParentPin", { pin: "0000" }), { ok: false });
  assert.deepEqual(await parent.call("verifyParentPin", { pin: "1357" }), { ok: true });
  const pin = (await adb.doc(`users/${parent.uid}/private/pin`).get()).data();
  assert.ok(pin.salt);
});

test("PIN: Kindergerät hat keinen Zugriff", async () => {
  const parent = await parentWithChildren();
  await parent.call("setParentPin", { pin: "4711" });
  const { code } = await parent.call("createPairingCode", { childId: "jan" });
  const kid = device();
  const { token } = await kid.call("redeemPairingCode", { code });
  await signInWithCustomToken(kid.auth, token);
  await expectError(kid.call("verifyParentPin", { pin: "4711" }), "permission-denied");
  await expectError(kid.call("setParentPin", { pin: "1111" }), "permission-denied");
  await signOut(kid.auth);
});
