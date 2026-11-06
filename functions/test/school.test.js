// Schule (functions/school.js + Rules) im Emulator. Starten mit: npm run test:emulator
const test = require("node:test");
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test("Schul-Tests brauchen den Emulator (npm run test:emulator)", { skip: true });
  return;
}

const {
  adb, device, parentWithChildren, expectError, closeDevices,
  signInWithCustomToken, doc, getDoc, setDoc, adminAuth, Timestamp,
  createUserWithEmailAndPassword,
} = require("./_client");
const { collection, getDocs } = require("firebase/firestore");
const { newPairingCode } = require("../lib/helpers");

test.after(closeDevices);

/** Einladungscode für eine Schule, wie ihn tool/admin/schule.py anlegt. */
async function schoolSignup(fields = {}) {
  const code = newPairingCode();
  await adb.doc(`schoolSignups/${code}`).set({
    expiresAt: Timestamp.fromMillis(Date.now() + 3600e3),
    ...fields,
  });
  return code;
}

/** Neues Konto ohne Kinder (wie über den Schul-Link registriert). */
async function freshAccount() {
  const d = device();
  const email = `s${Date.now()}${Math.random().toString(36).slice(2, 6)}@schule.de`;
  const { user } = await createUserWithEmailAndPassword(d.auth, email, "geheim123");
  return { ...d, uid: user.uid };
}

/** Konto anlegen, Schule gründen, Token mit den neuen Claims holen. */
async function schoolAdmin(name = "Grundschule am Wald", account = null) {
  const admin = account || (await parentWithChildren());
  const code = await schoolSignup();
  const { schoolId } = await admin.call("createSchool", { code, name });
  await admin.auth.currentUser.getIdToken(true);
  return { ...admin, schoolId, owner: `school_${schoolId}` };
}

/**
 * Schule mit Schulleitung, dazu eine Lehrkraft, die sich mit Karte + PIN
 * anmeldet (wie ein Lehrergerät). Gibt das Lehrergerät zurück.
 */
async function schoolTeacher(name = "Grundschule am Wald") {
  const admin = await schoolAdmin(name, await freshAccount());
  const { teacherId, token } = await admin.call("createTeacher", { name: "Herr Becker" });
  const teacher = device();
  const { token: custom } = await teacher.call("redeemTeacherCard", { token, newPin: "2468" });
  await signInWithCustomToken(teacher.auth, custom);
  return { ...teacher, uid: teacher.auth.currentUser.uid, teacherId, cardToken: token,
    schoolId: admin.schoolId, owner: admin.owner, admin };
}

/** Schüler anlegen, wie es die App tut (über die Rules, nicht die Function). */
async function addStudent(teacher, owner, id, name, classId = "5b") {
  await setDoc(doc(teacher.db, `users/${owner}/children/${id}`), {
    name, grade: 5, classId, xp: 0, level: 1,
  });
}

async function studentDevice(token) {
  const kid = device();
  const { token: custom, childName } = await kid.call("redeemStudentCard", { token });
  const { user } = await signInWithCustomToken(kid.auth, custom);
  return { ...kid, user, childName };
}

test("Schule anlegen: Admin-Claims, Schul-Konto, nur einmal", async () => {
  const admin = await schoolAdmin();
  const { claims } = await admin.auth.currentUser.getIdTokenResult();
  assert.equal(claims.schoolId, admin.schoolId);
  assert.equal(claims.schoolRole, "admin");
  assert.equal(claims.role, undefined); // bleibt für die eigene Familie „Eltern“

  const school = await getDoc(doc(admin.db, `schools/${admin.schoolId}`));
  assert.equal(school.get("name"), "Grundschule am Wald");
  const owner = await getDoc(doc(admin.db, `users/${admin.owner}`));
  assert.equal(owner.get("isSchool"), true);

  const second = await schoolSignup();
  await expectError(admin.call("createSchool", { code: second, name: "Zweite Schule" }), "already-exists");
  await expectError(device().call("createSchool", { code: second, name: "Ohne Konto" }), "unauthenticated");
  // Elternkonto mit Kindern bleibt Elternkonto (kein reines Schulkonto)
  assert.equal((await adb.doc(`users/${admin.uid}`).get()).get("accountType"), undefined);
});

test("Schule anlegen: Lerndex bekommt eine Mail", async () => {
  const account = await freshAccount();
  const code = await schoolSignup({ licenseUntil: Timestamp.fromDate(new Date("2027-07-31T21:59:59Z")) });
  const { schoolId } = await account.call("createSchool", { code, name: "Realschule Lengerich" });
  const mails = await adb.collection("mail").where("schoolId", "==", schoolId).get();
  assert.equal(mails.size, 1);
  const mail = mails.docs[0].data();
  assert.equal(mail.type, "schoolCreated");
  assert.deepEqual(mail.to, ["support@lerndex.de"]);
  assert.equal(mail.message.subject, "Neue Schule: Realschule Lengerich");
  assert.match(mail.message.text, /Lizenz bis:\s+31\.7\.2027/);
  assert.match(mail.message.text, /@schule\.de/);
  assert.match(mail.message.text, new RegExp(code));
});

test("Schule anlegen nur mit Einladungscode von Lerndex", async () => {
  const account = await freshAccount();
  await expectError(account.call("createSchool", { name: "Ohne Code" }), "not-found");
  await expectError(account.call("createSchool", { code: "ABCDEFGH", name: "Falscher Code" }), "not-found");
  const expired = await schoolSignup({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
  await expectError(account.call("createSchool", { code: expired, name: "Abgelaufen" }), "not-found");

  // Ohne Namen (und ohne Namen im Code) geht es nicht – der Code bleibt gültig
  const code = await schoolSignup({ licenseUntil: Timestamp.fromMillis(Date.UTC(2027, 6, 31)) });
  await expectError(account.call("createSchool", { code }), "invalid-argument");
  const result = await account.call("createSchool", { code: code.toLowerCase(), name: " Schule am See " });
  assert.equal(result.schoolName, "Schule am See");
  assert.equal(result.schoolAccount, true);

  // Lizenz aus dem Code, Code verbraucht, Konto ist reines Schulkonto
  const owner = await adb.doc(`users/school_${result.schoolId}`).get();
  assert.equal(owner.get("schoolLicenseUntil").toMillis(), Date.UTC(2027, 6, 31));
  assert.equal((await adb.doc(`schoolSignups/${code}`).get()).exists, false);
  const user = (await adb.doc(`users/${account.uid}`).get()).data();
  assert.equal(user.accountType, "school");
  assert.equal(user.schoolId, result.schoolId);
  assert.equal(user.onboardingCompleted, true);

  // Name aus dem Code, wenn die Schule keinen angibt
  const named = await schoolSignup({ schoolName: "Realschule Nord" });
  const other = await freshAccount();
  assert.equal((await other.call("createSchool", { code: named })).schoolName, "Realschule Nord");
});

test("Lehrkraft: eigene Kinder weiter erreichbar, Schul-Konto nicht änderbar", async () => {
  const admin = await schoolAdmin();
  assert.equal((await getDoc(doc(admin.db, `users/${admin.uid}/children/jan`))).get("name"), "Jan");
  await assert.rejects(setDoc(doc(admin.db, `users/${admin.owner}`), {
    schoolLicenseUntil: new Date(2099, 0, 1),
  }, { merge: true }));
  await assert.rejects(setDoc(doc(admin.db, `schools/${admin.schoolId}`), { name: "X" }));
  // Die Schulleitung verwaltet nur Lehrkräfte: keine Klassen, keine Schüler
  await assert.rejects(setDoc(doc(admin.db, `schools/${admin.schoolId}/classes/5b`), { name: "5b" }));
  await assert.rejects(setDoc(doc(admin.db, `users/${admin.owner}/children/s1`), { name: "Mia" }));
  await expectError(admin.call("createStudentCards", { studentIds: ["s1"] }), "permission-denied");
});

test("Lehrkraft: Karte + PIN, sieht alle Klassen und Schüler", async () => {
  const admin = await schoolAdmin("Grundschule am Wald", await freshAccount());
  const { teacherId, token } = await admin.call("createTeacher", { name: "  Frau Lindner " });
  assert.match(token, /^[A-HJ-NP-Z2-9]{20}$/);
  const member = (await adb.doc(`schools/${admin.schoolId}/members/${teacherId}`).get()).data();
  assert.equal(member.name, "Frau Lindner");
  assert.equal(member.pinSet, false);

  // Erstes Scannen: PIN festlegen
  const t = device();
  assert.deepEqual(await t.call("redeemTeacherCard", { token }), { pinSet: false, name: "Frau Lindner" });
  await expectError(t.call("redeemTeacherCard", { token, newPin: "12" }), "invalid-argument");
  const first = await t.call("redeemTeacherCard", { token, newPin: "4711" });
  const { user } = await signInWithCustomToken(t.auth, first.token);
  assert.equal(user.uid, `teacher:${admin.schoolId}:${teacherId}`);
  const { claims } = await user.getIdTokenResult();
  assert.equal(claims.role, "teacher");
  assert.equal(claims.schoolRole, "teacher");
  assert.equal(claims.schoolId, admin.schoolId);

  // Danach nur mit PIN; PIN nicht nochmal neu setzbar, Hash nicht lesbar
  const other = device();
  assert.deepEqual(await other.call("redeemTeacherCard", { token }), { pinSet: true, name: "Frau Lindner" });
  assert.deepEqual(await other.call("redeemTeacherCard", { token, newPin: "0000" }), { pinSet: true, name: "Frau Lindner" });
  assert.deepEqual(await other.call("redeemTeacherCard", { token, pin: "0000" }), { ok: false });
  assert.ok((await other.call("redeemTeacherCard", { token, pin: "4711" })).token);
  await assert.rejects(getDoc(doc(t.db, `schools/${admin.schoolId}/members/${teacherId}/private/pin`)));

  // Klassen und Schüler anlegen, alles sehen
  await setDoc(doc(t.db, `schools/${admin.schoolId}/classes/5b`), { name: "5b", grade: 5 });
  await addStudent(t, admin.owner, "s1", "Mia");
  assert.equal((await getDoc(doc(t.db, `users/${admin.owner}/children/s1`))).get("name"), "Mia");
  const members = await getDocs(collection(t.db, `schools/${admin.schoolId}/members`));
  assert.equal(members.size, 2);

  // Lehrergeräte sind keine Eltern und keine Schulleitung
  await expectError(t.call("createPairingCode", { childId: "s1" }), "permission-denied");
  await expectError(t.call("createTeacher", { name: "X" }), "permission-denied");
  await assert.rejects(setDoc(doc(t.db, `users/${user.uid}`), { a: 1 }));

  await expectError(device().call("redeemTeacherCard", { token: "X".repeat(20) }), "not-found");
  await expectError(admin.call("createTeacher", { name: "" }), "invalid-argument");
});

test("Lehrkraft: nach 5 falschen PINs gesperrt, PIN zurücksetzen", async () => {
  const teacher = await schoolTeacher();
  const d = device();
  for (let i = 0; i < 5; i++) {
    assert.deepEqual(await d.call("redeemTeacherCard", { token: teacher.cardToken, pin: "0000" }), { ok: false });
  }
  await expectError(d.call("redeemTeacherCard", { token: teacher.cardToken, pin: "2468" }), "resource-exhausted");

  // Schulleitung: neue Karte mit PIN-Reset; alte Karte ungültig
  const { token } = await teacher.admin.call("reissueTeacherCard", { teacherId: teacher.teacherId, resetPin: true });
  await expectError(d.call("redeemTeacherCard", { token: teacher.cardToken }), "not-found");
  assert.equal((await d.call("redeemTeacherCard", { token })).pinSet, false);
  assert.ok((await d.call("redeemTeacherCard", { token, newPin: "1357" })).token);
  await expectError(teacher.call("reissueTeacherCard", { teacherId: teacher.teacherId }), "permission-denied");
});

test("Lexi-Chats der Schüler sind für Lehrkräfte privat", async () => {
  const admin = await schoolTeacher();
  await addStudent(admin, admin.owner, "s1", "Mia");
  await setDoc(doc(admin.db, `users/${admin.owner}/children/s1/rewards/r1`), { title: "a" });
  await assert.rejects(
    setDoc(doc(admin.db, `users/${admin.owner}/children/s1/tutor_sessions/t1`), { a: 1 }),
  );
  await assert.rejects(
    getDocs(collection(admin.db, `users/${admin.owner}/children/s1/tutor_sessions`)),
  );
});

test("Schulen und Familien sind getrennt", async () => {
  const a = await schoolTeacher("Schule A");
  const b = await schoolTeacher("Schule B");
  await addStudent(a, a.owner, "s1", "Mia");
  await assert.rejects(getDoc(doc(b.db, `users/${a.owner}/children/s1`)));
  await assert.rejects(getDoc(doc(b.db, `schools/${a.schoolId}`)));
  const family = await parentWithChildren();
  await assert.rejects(getDoc(doc(a.db, `users/${family.uid}/children/jan`)));

  const parent = await parentWithChildren();
  await assert.rejects(getDoc(doc(parent.db, `users/${a.owner}/children/s1`)));
  await assert.rejects(getDoc(doc(parent.db, `users/${a.owner}`)));
});

test("Karten: einlösen, wiederverwenden, nur eigener Schüler", async () => {
  const admin = await schoolTeacher();
  await addStudent(admin, admin.owner, "s1", "Mia");
  await addStudent(admin, admin.owner, "s2", "Ben");
  const { cards } = await admin.call("createStudentCards", { studentIds: ["s1", "s2"] });
  assert.equal(cards.length, 2);
  assert.match(cards[0].token, /^[A-HJ-NP-Z2-9]{20}$/);

  // Nur der Hash liegt in der Datenbank
  const stored = await adb.collection("studentCards").where("schoolId", "==", admin.schoolId).get();
  assert.equal(stored.size, 2);
  assert.ok(stored.docs.every((d) => d.id !== cards[0].token));

  const mia = await studentDevice(cards[0].token);
  assert.equal(mia.childName, "Mia");
  assert.equal(mia.user.uid, `kid:${admin.owner}:s1`);
  const { claims } = await mia.user.getIdTokenResult();
  assert.equal(claims.role, "student");
  assert.equal(claims.schoolId, admin.schoolId);

  assert.equal((await getDoc(doc(mia.db, `users/${admin.owner}/children/s1`))).get("name"), "Mia");
  await assert.rejects(getDoc(doc(mia.db, `users/${admin.owner}/children/s2`)));
  await assert.rejects(getDoc(doc(mia.db, `schools/${admin.schoolId}`)));
  // Schul-Konto (Lizenz) lesen geht
  assert.equal((await getDoc(doc(mia.db, `users/${admin.owner}`))).get("isSchool"), true);
  // Eigene Lexi-Chats schon
  await setDoc(doc(mia.db, `users/${admin.owner}/children/s1/tutor_sessions/t1`), { a: 1 });

  // Geteiltes Tablet: dieselbe Karte geht wieder
  await studentDevice(cards[0].token);
  await expectError(device().call("redeemStudentCard", { token: "X".repeat(20) }), "not-found");
  await expectError(device().call("redeemStudentCard", {}), "not-found");
});

test("Karten: neu drucken macht alte ungültig, Sperren löscht das Konto", async () => {
  const admin = await schoolTeacher();
  await addStudent(admin, admin.owner, "s1", "Mia");
  const first = (await admin.call("createStudentCards", { studentIds: ["s1"] })).cards[0];
  const second = (await admin.call("createStudentCards", { studentIds: ["s1"] })).cards[0];
  await expectError(device().call("redeemStudentCard", { token: first.token }), "not-found");
  await studentDevice(second.token);

  const { revokedCards } = await admin.call("revokeStudent", { studentId: "s1" });
  assert.equal(revokedCards, 1);
  await expectError(device().call("redeemStudentCard", { token: second.token }), "not-found");
  await assert.rejects(adminAuth().getUser(`kid:${admin.owner}:s1`));
});

test("Karten nur für Lehrkräfte und eigene Schüler", async () => {
  const a = await schoolTeacher("Schule A");
  const b = await schoolTeacher("Schule B");
  await addStudent(a, a.owner, "s1", "Mia");
  await expectError(b.call("createStudentCards", { studentIds: ["s1"] }), "not-found");
  await expectError((await parentWithChildren()).call("createStudentCards", { studentIds: ["s1"] }), "permission-denied");
  await expectError(a.call("createStudentCards", { studentIds: [] }), "invalid-argument");
});

test("Lehrkraft entfernen: Konto, Karte und PIN weg", async () => {
  const teacher = await schoolTeacher();
  const admin = teacher.admin;
  await expectError(admin.call("removeTeacher", { uid: admin.uid }), "invalid-argument");
  await admin.call("removeTeacher", { uid: teacher.teacherId });
  await assert.rejects(adminAuth().getUser(teacher.uid));
  await expectError(device().call("redeemTeacherCard", { token: teacher.cardToken }), "not-found");
  assert.equal((await adb.doc(`schools/${admin.schoolId}/members/${teacher.teacherId}/private/pin`).get()).exists, false);
  const members = await adb.collection(`schools/${admin.schoolId}/members`).get();
  assert.equal(members.size, 1);
});

test("Konto der Schulleitung gelöscht: aus der Liste ausgetragen", async () => {
  const admin = await schoolAdmin("Schule X", await freshAccount());
  await adminAuth().deleteUser(admin.uid);
  let left = 1;
  for (let i = 0; i < 40 && left > 0; i++) {
    await new Promise((r) => setTimeout(r, 250));
    left = (await adb.collection(`schools/${admin.schoolId}/members`).get()).size;
  }
  assert.equal(left, 0);
});

test("Schüler löschen: Daten inkl. Lexi-Chats, Karten und Konto weg", async () => {
  const admin = await schoolTeacher();
  await addStudent(admin, admin.owner, "s1", "Mia");
  const { cards } = await admin.call("createStudentCards", { studentIds: ["s1"] });
  const mia = await studentDevice(cards[0].token);
  await setDoc(doc(mia.db, `users/${admin.owner}/children/s1/tutor_sessions/t1`), { a: 1 });
  await setDoc(doc(mia.db, `users/${admin.owner}/children/s1/tutor_sessions/t1/messages/m1`), { t: "hi" });

  await adb.doc(`users/${admin.owner}/generated_batches/b1`).set({ childId: "s1", classId: "c1" });
  await adb.doc(`users/${admin.owner}/generated_batches/b1/questions/q1`).set({ q: "1+1" });
  await adb.doc(`users/${admin.owner}/generated_batches/b2`).set({ childId: "s2", classId: "c1" });
  await adb.doc(`aiUsage/kid:${admin.owner}:s1`).set({ count: 3 });

  await admin.call("deleteStudent", { studentId: "s1" });

  assert.equal((await adb.doc(`users/${admin.owner}/children/s1`).get()).exists, false);
  assert.equal((await adb.doc(`users/${admin.owner}/generated_batches/b1`).get()).exists, false);
  assert.equal((await adb.doc(`users/${admin.owner}/generated_batches/b1/questions/q1`).get()).exists, false);
  assert.equal((await adb.doc(`users/${admin.owner}/generated_batches/b2`).get()).exists, true);
  assert.equal((await adb.doc(`aiUsage/kid:${admin.owner}:s1`).get()).exists, false);
  assert.equal((await adb.doc(`users/${admin.owner}/children/s1/tutor_sessions/t1/messages/m1`).get()).exists, false);
  await expectError(device().call("redeemStudentCard", { token: cards[0].token }), "not-found");
  await assert.rejects(adminAuth().getUser(`kid:${admin.owner}:s1`));
  await expectError((await parentWithChildren()).call("deleteStudent", { studentId: "s1" }), "permission-denied");
});

// ── Eltern verbinden (Elternbrief) ──────────────────────────────────────────

test("Elternbrief: Eltern verbinden sich, sehen ihr Schulkind, nur das eigene", async () => {
  const teacher = await schoolTeacher();
  await addStudent(teacher, teacher.owner, "s1", "Mia");
  await addStudent(teacher, teacher.owner, "s2", "Ben");
  await setDoc(doc(teacher.db, `users/${teacher.owner}/children/s1/tutor_sessions/t1`), { a: 1 }).catch(() => {});
  await adb.doc(`users/${teacher.owner}/children/s1/tutor_sessions/t1`).set({ topic: "Brüche" });
  await adb.doc(`users/${teacher.owner}/children/s1/tutor_sessions/t1/messages/m1`).set({ text: "hi" });

  const { letters } = await teacher.call("createParentLetters", { studentIds: ["s1"] });
  assert.equal(letters.length, 1);
  assert.match(letters[0].parentCode, /^[A-HJ-NP-Z2-9]{8}$/);

  const parent = await parentWithChildren();
  // Vorschau verbindet noch nicht
  const preview = await parent.call("previewSchoolChild", { code: letters[0].parentCode });
  assert.equal(preview.firstName, "Mia");
  assert.equal((await adb.doc(`users/${teacher.owner}/children/s1`).get()).get("parentUids"), undefined);
  await expectError(parent.call("previewSchoolChild", { code: "ABCDEFGH" }), "not-found");

  const linked = await parent.call("linkSchoolChild", { code: letters[0].parentCode.toLowerCase() });
  assert.equal(linked.name, "Mia");
  assert.equal(linked.ownerUid, teacher.owner);
  const link = await getDoc(doc(parent.db, `users/${parent.uid}/linkedChildren/${teacher.schoolId}_s1`));
  assert.equal(link.get("studentId"), "s1");

  // Lesen: Kind, Lexi-Gespräche; Belohnungen schreiben; nicht das Geschwisterkind
  assert.equal((await getDoc(doc(parent.db, `users/${teacher.owner}/children/s1`))).get("name"), "Mia");
  assert.equal((await getDoc(doc(parent.db,
    `users/${teacher.owner}/children/s1/tutor_sessions/t1/messages/m1`))).get("text"), "hi");
  await setDoc(doc(parent.db, `users/${teacher.owner}/children/s1/rewards/r1`), { title: "Eis" });
  await assert.rejects(getDoc(doc(parent.db, `users/${teacher.owner}/children/s2`)));
  await assert.rejects(setDoc(doc(parent.db, `users/${teacher.owner}/children/s1`), { name: "X" }, { merge: true }));
  await assert.rejects(setDoc(doc(parent.db, `users/${teacher.owner}/children/s1/learning_stats/d`), { a: 1 }));
  await assert.rejects(getDoc(doc(parent.db, `schools/${teacher.schoolId}`)));

  // parentUids kann niemand selbst setzen
  const other = await parentWithChildren();
  await assert.rejects(getDoc(doc(other.db, `users/${teacher.owner}/children/s1`)));
  await assert.rejects(setDoc(doc(teacher.db, `users/${teacher.owner}/children/s1`),
    { parentUids: [other.uid] }, { merge: true }));
  await assert.rejects(setDoc(doc(teacher.db, `users/${teacher.owner}/children/s9`),
    { name: "Neu", parentUids: [other.uid] }));

  // Heimkarte aus dem Brief meldet das Kind an und überlebt neue Schulkarten
  await teacher.call("createStudentCards", { studentIds: ["s1"] });
  const home = await studentDevice(letters[0].homeToken);
  assert.equal(home.childName, "Mia");
  // Kindergerät darf parentUids nicht ändern
  await assert.rejects(setDoc(doc(home.db, `users/${teacher.owner}/children/s1`),
    { parentUids: [] }, { merge: true }));

  // Trennen
  await parent.call("unlinkSchoolChild", { schoolId: teacher.schoolId, studentId: "s1" });
  await assert.rejects(getDoc(doc(parent.db, `users/${teacher.owner}/children/s1`)));

  // Lehrergerät und Kindergerät können keine Kinder verbinden
  await expectError(teacher.call("linkSchoolChild", { code: letters[0].parentCode }), "permission-denied");
  await expectError(parent.call("linkSchoolChild", { code: "ABCDEFGH" }), "not-found");
});

test("Elternbrief: neuer Brief macht alten Code ungültig, Schüler löschen trennt Eltern", async () => {
  const teacher = await schoolTeacher();
  await addStudent(teacher, teacher.owner, "s1", "Mia");
  const first = (await teacher.call("createParentLetters", { studentIds: ["s1"] })).letters[0];
  const second = (await teacher.call("createParentLetters", { studentIds: ["s1"] })).letters[0];
  const parent = await parentWithChildren();
  await expectError(parent.call("linkSchoolChild", { code: first.parentCode }), "not-found");
  await expectError(device().call("redeemStudentCard", { token: first.homeToken }), "not-found");
  await parent.call("linkSchoolChild", { code: second.parentCode });

  await teacher.call("deleteStudent", { studentId: "s1" });
  assert.equal((await adb.doc(`users/${parent.uid}/linkedChildren/${teacher.schoolId}_s1`).get()).exists, false);
  await expectError(parent.call("linkSchoolChild", { code: second.parentCode }), "not-found");
});
