// Schule (functions/school.js + Rules) im Emulator. Starten mit: npm run test:emulator
const test = require("node:test");
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test("Schul-Tests brauchen den Emulator (npm run test:emulator)", { skip: true });
  return;
}

const {
  adb, device, parentWithChildren, expectError, closeDevices,
  signInWithCustomToken, doc, getDoc, setDoc, adminAuth,
} = require("./_client");
const { collection, getDocs } = require("firebase/firestore");

test.after(closeDevices);

/** Konto anlegen, Schule gründen, Token mit den neuen Claims holen. */
async function schoolAdmin(name = "Grundschule am Wald") {
  const admin = await parentWithChildren();
  const { schoolId } = await admin.call("createSchool", { name });
  await admin.auth.currentUser.getIdToken(true);
  return { ...admin, schoolId, owner: `school_${schoolId}` };
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

  await expectError(admin.call("createSchool", { name: "Zweite Schule" }), "already-exists");
  await expectError(device().call("createSchool", { name: "Ohne Konto" }), "unauthenticated");
});

test("Lehrkraft: eigene Kinder weiter erreichbar, Schul-Konto nicht änderbar", async () => {
  const admin = await schoolAdmin();
  assert.equal((await getDoc(doc(admin.db, `users/${admin.uid}/children/jan`))).get("name"), "Jan");
  await assert.rejects(setDoc(doc(admin.db, `users/${admin.owner}`), {
    schoolLicenseUntil: new Date(2099, 0, 1),
  }, { merge: true }));
  await assert.rejects(setDoc(doc(admin.db, `schools/${admin.schoolId}`), { name: "X" }));
});

test("Einladen: Lehrkraft tritt bei, sieht alle Schüler", async () => {
  const admin = await schoolAdmin();
  await addStudent(admin, admin.owner, "s1", "Mia");
  await setDoc(doc(admin.db, `schools/${admin.schoolId}/classes/5b`), { name: "5b", grade: 5 });

  const { code } = await admin.call("createTeacherInvite", {});
  const teacher = await parentWithChildren();
  const joined = await teacher.call("joinSchool", { code: code.toLowerCase() });
  assert.equal(joined.schoolName, "Grundschule am Wald");
  await teacher.auth.currentUser.getIdToken(true);

  // Alle Klassen, alle Schüler
  assert.equal((await getDoc(doc(teacher.db, `users/${admin.owner}/children/s1`))).get("name"), "Mia");
  const classes = await getDocs(collection(teacher.db, `schools/${admin.schoolId}/classes`));
  assert.equal(classes.size, 1);
  const members = await getDocs(collection(teacher.db, `schools/${admin.schoolId}/members`));
  assert.equal(members.size, 2);

  // Code nur einmal, nur Admins laden ein
  await expectError((await parentWithChildren()).call("joinSchool", { code }), "not-found");
  await expectError(teacher.call("createTeacherInvite", {}), "permission-denied");
  await expectError(teacher.call("joinSchool", { code: "ABCDEFGH" }), "already-exists");
});

test("Lexi-Chats der Schüler sind für Lehrkräfte privat", async () => {
  const admin = await schoolAdmin();
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
  const a = await schoolAdmin("Schule A");
  const b = await schoolAdmin("Schule B");
  await addStudent(a, a.owner, "s1", "Mia");
  await assert.rejects(getDoc(doc(b.db, `users/${a.owner}/children/s1`)));
  await assert.rejects(getDoc(doc(b.db, `schools/${a.schoolId}`)));
  await assert.rejects(getDoc(doc(a.db, `users/${b.uid}/children/jan`)));

  const parent = await parentWithChildren();
  await assert.rejects(getDoc(doc(parent.db, `users/${a.owner}/children/s1`)));
  await assert.rejects(getDoc(doc(parent.db, `users/${a.owner}`)));
});

test("Karten: einlösen, wiederverwenden, nur eigener Schüler", async () => {
  const admin = await schoolAdmin();
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
  const admin = await schoolAdmin();
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
  const a = await schoolAdmin("Schule A");
  const b = await schoolAdmin("Schule B");
  await addStudent(a, a.owner, "s1", "Mia");
  await expectError(b.call("createStudentCards", { studentIds: ["s1"] }), "not-found");
  await expectError((await parentWithChildren()).call("createStudentCards", { studentIds: ["s1"] }), "permission-denied");
  await expectError(a.call("createStudentCards", { studentIds: [] }), "invalid-argument");
});

test("Lehrkraft entfernen", async () => {
  const admin = await schoolAdmin();
  const { code } = await admin.call("createTeacherInvite", {});
  const teacher = await parentWithChildren();
  await teacher.call("joinSchool", { code });

  await expectError(admin.call("removeTeacher", { uid: admin.uid }), "invalid-argument");
  await admin.call("removeTeacher", { uid: teacher.uid });
  const user = await adminAuth().getUser(teacher.uid);
  assert.equal(user.customClaims?.schoolId, undefined);
  const members = await adb.collection(`schools/${admin.schoolId}/members`).get();
  assert.equal(members.size, 1);
});

test("Lehrerkonto gelöscht: aus der Lehrerliste ausgetragen", async () => {
  const admin = await schoolAdmin();
  const { code } = await admin.call("createTeacherInvite", {});
  const teacher = await parentWithChildren();
  await teacher.call("joinSchool", { code });
  await adminAuth().deleteUser(teacher.uid);

  let left = 2;
  for (let i = 0; i < 40 && left > 1; i++) {
    await new Promise((r) => setTimeout(r, 250));
    left = (await adb.collection(`schools/${admin.schoolId}/members`).get()).size;
  }
  assert.equal(left, 1);
});


test("Schüler löschen: Daten inkl. Lexi-Chats, Karten und Konto weg", async () => {
  const admin = await schoolAdmin();
  await addStudent(admin, admin.owner, "s1", "Mia");
  const { cards } = await admin.call("createStudentCards", { studentIds: ["s1"] });
  const mia = await studentDevice(cards[0].token);
  await setDoc(doc(mia.db, `users/${admin.owner}/children/s1/tutor_sessions/t1`), { a: 1 });
  await setDoc(doc(mia.db, `users/${admin.owner}/children/s1/tutor_sessions/t1/messages/m1`), { t: "hi" });

  await admin.call("deleteStudent", { studentId: "s1" });

  assert.equal((await adb.doc(`users/${admin.owner}/children/s1`).get()).exists, false);
  assert.equal((await adb.doc(`users/${admin.owner}/children/s1/tutor_sessions/t1/messages/m1`).get()).exists, false);
  await expectError(device().call("redeemStudentCard", { token: cards[0].token }), "not-found");
  await assert.rejects(adminAuth().getUser(`kid:${admin.owner}:s1`));
  await expectError((await parentWithChildren()).call("deleteStudent", { studentId: "s1" }), "permission-denied");
});
