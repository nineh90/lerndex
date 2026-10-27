// Cloud Functions im Emulator. Starten mit: npm run test:emulator
const test = require("node:test");
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test("Function-Tests brauchen den Emulator (npm run test:emulator)", { skip: true });
  return;
}

const { hashPin, legacyHashPin } = require("../lib/helpers");
const {
  adb, device, parentWithChildren, expectError, closeDevices,
  signInWithCustomToken, signOut, doc, getDoc, Timestamp, adminAuth,
} = require("./_client");

test.after(closeDevices);

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

test("Abmelden: Kinderkonto gelöscht, Geräte weg, neu koppeln geht", async () => {
  const parent = await parentWithChildren();
  const { code } = await parent.call("createPairingCode", { childId: "jan" });
  await device().call("redeemPairingCode", { code });

  const { unpaired } = await parent.call("unpairChildDevices", { childId: "jan" });
  assert.equal(unpaired, 1);
  await assert.rejects(adminAuth().getUser(`kid:${parent.uid}:jan`), (e) => {
    assert.equal(e.code, "auth/user-not-found");
    return true;
  });
  assert.equal((await adb.collection(`users/${parent.uid}/children/jan/devices`).get()).size, 0);

  // Ohne gekoppeltes Gerät: kein Fehler
  assert.equal((await parent.call("unpairChildDevices", { childId: "max" })).unpaired, 0);

  const again = await parent.call("createPairingCode", { childId: "jan" });
  await device().call("redeemPairingCode", { code: again.code });
  const kidUser = await adminAuth().getUser(`kid:${parent.uid}:jan`);
  assert.equal(kidUser.displayName, undefined); // kein Kindername im Konto
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

// ── Aufräumen ────────────────────────────────────────────────────────────────

test("Elternkonto gelöscht: PIN und offene Codes weg", async () => {
  const parent = await parentWithChildren();
  await parent.call("setParentPin", { pin: "4711" });
  await parent.call("createPairingCode", { childId: "jan" });

  await adminAuth().deleteUser(parent.uid);

  // Der Trigger läuft asynchron
  let pinExists = true;
  let openCodes = 1;
  for (let i = 0; i < 40 && (pinExists || openCodes > 0); i++) {
    await new Promise((r) => setTimeout(r, 250));
    pinExists = (await adb.doc(`users/${parent.uid}/private/pin`).get()).exists;
    openCodes = (await adb.collection("pairingCodes").where("parentUid", "==", parent.uid).get()).size;
  }
  assert.equal(pinExists, false);
  assert.equal(openCodes, 0);
});
