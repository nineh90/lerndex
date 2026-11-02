// Firestore-/Storage-Rules im Emulator. Starten mit: npm run test:emulator
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs,
} = require("firebase/firestore");
const { ref, uploadBytes } = require("firebase/storage");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test("Rules-Tests brauchen den Emulator (npm run test:emulator)", { skip: true });
  return;
}

const root = path.join(__dirname, "..", "..");
const [fsHost, fsPort] = process.env.FIRESTORE_EMULATOR_HOST.split(":");
const [stHost, stPort] = process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(":");

let env;
const PARENT = "parent1";
const OTHER = "parent2";
const CHILD = "child1";
const SIBLING = "child2";

const parent = () => env.authenticatedContext(PARENT).firestore();
const otherParent = () => env.authenticatedContext(OTHER).firestore();
const student = (childId = CHILD, parentUid = PARENT) =>
  env.authenticatedContext(`kid:${parentUid}:${childId}`, {
    role: "student", parentUid, childId,
  });

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-lerndex",
    firestore: {
      host: fsHost, port: Number(fsPort),
      rules: fs.readFileSync(path.join(root, "firestore.rules"), "utf8"),
    },
    storage: {
      host: stHost, port: Number(stPort),
      rules: fs.readFileSync(path.join(root, "storage.rules"), "utf8"),
    },
  });
});

test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${PARENT}`), { plan: "family", testAccess: false });
    await setDoc(doc(db, `users/${PARENT}/private/pin`), { hash: "x", salt: "y" });
    await setDoc(doc(db, `users/${PARENT}/children/${CHILD}`), { name: "Jan", xp: 10 });
    await setDoc(doc(db, `users/${PARENT}/children/${SIBLING}`), { name: "Max", xp: 0 });
    await setDoc(doc(db, `users/${PARENT}/children/${CHILD}/rewards/r1`), { title: "a" });
    await setDoc(doc(db, `users/${PARENT}/children/${CHILD}/devices/d1`), { pairedAt: 1 });
    await setDoc(doc(db, `users/${PARENT}/children/${CHILD}/tutor_sessions/s1/messages/m1`), { text: "hi" });
    await setDoc(doc(db, `users/${PARENT}/generated_batches/b1`), { childId: CHILD });
    await setDoc(doc(db, `users/${PARENT}/generated_batches/b1/questions/q1`), { status: "approved" });
    await setDoc(doc(db, `users/${PARENT}/generated_batches/b2`), { childId: SIBLING });
    await setDoc(doc(db, `users/${PARENT}/generated_batches/b2/questions/q1`), { status: "approved" });
    await setDoc(doc(db, "pairingCodes/ABCDEFGH"), { parentUid: PARENT, childId: CHILD });
  });
});

test.after(async () => {
  await env?.cleanup();
});

// ── Eltern ───────────────────────────────────────────────────────────────────

test("Eltern: eigene Daten ja, fremde nein", async () => {
  await assertSucceeds(getDoc(doc(parent(), `users/${PARENT}/children/${CHILD}`)));
  await assertSucceeds(setDoc(doc(parent(), `users/${PARENT}/children/c3`), { name: "Neu" }));
  await assertFails(getDoc(doc(otherParent(), `users/${PARENT}`)));
  await assertFails(getDoc(doc(otherParent(), `users/${PARENT}/children/${CHILD}`)));
});

test("Eltern: PIN, testAccess und pinSet nicht selbst setzbar", async () => {
  await assertFails(getDoc(doc(parent(), `users/${PARENT}/private/pin`)));
  await assertFails(setDoc(doc(parent(), `users/${PARENT}/private/pin`), { hash: "z" }));
  await assertFails(updateDoc(doc(parent(), `users/${PARENT}`), { testAccess: true }));
  await assertFails(updateDoc(doc(parent(), `users/${PARENT}`), { pinSet: true }));
  await assertSucceeds(updateDoc(doc(parent(), `users/${PARENT}`), { displayName: "K" }));
});

test("Eltern: Kopplungscodes nur über die Function", async () => {
  await assertFails(getDoc(doc(parent(), "pairingCodes/ABCDEFGH")));
  await assertFails(setDoc(doc(parent(), "pairingCodes/XYZXYZXY"), { parentUid: PARENT }));
});

// ── Kindergerät ──────────────────────────────────────────────────────────────

test("Kindergerät: eigenes Kind lesen und Fortschritt speichern", async () => {
  const db = student().firestore();
  await assertSucceeds(getDoc(doc(db, `users/${PARENT}/children/${CHILD}`)));
  await assertSucceeds(updateDoc(doc(db, `users/${PARENT}/children/${CHILD}`), { xp: 20 }));
  await assertSucceeds(getDoc(doc(db, `users/${PARENT}/children/${CHILD}/rewards/r1`)));
  await assertSucceeds(setDoc(doc(db, `users/${PARENT}/children/${CHILD}/rewards/r2`), { title: "b" }));
  await assertSucceeds(
    setDoc(doc(db, `users/${PARENT}/children/${CHILD}/tutor_sessions/s1/messages/m2`), { text: "x" }),
  );
});

test("Kindergerät: Kind nicht anlegen oder löschen", async () => {
  const db = student().firestore();
  await assertFails(deleteDoc(doc(db, `users/${PARENT}/children/${CHILD}`)));
  await assertFails(setDoc(doc(db, `users/${PARENT}/children/c9`), { name: "X" }));
});

test("Kindergerät: keine Geschwister, keine fremde Familie", async () => {
  const db = student().firestore();
  await assertFails(getDoc(doc(db, `users/${PARENT}/children/${SIBLING}`)));
  await assertFails(updateDoc(doc(db, `users/${PARENT}/children/${SIBLING}`), { xp: 99 }));
  await assertFails(getDocs(collection(db, `users/${PARENT}/children`)));
  await assertFails(getDoc(doc(db, `users/${OTHER}`)));
});

test("Kindergerät: Eltern-Dokument lesen, aber nicht ändern; kein PIN", async () => {
  const db = student().firestore();
  await assertSucceeds(getDoc(doc(db, `users/${PARENT}`)));
  await assertFails(updateDoc(doc(db, `users/${PARENT}`), { plan: "x" }));
  await assertFails(getDoc(doc(db, `users/${PARENT}/private/pin`)));
});

test("Kindergerät: Geräteliste ist Elternsache", async () => {
  const db = student().firestore();
  await assertFails(getDoc(doc(db, `users/${PARENT}/children/${CHILD}/devices/d1`)));
  await assertFails(setDoc(doc(db, `users/${PARENT}/children/${CHILD}/devices/d2`), { x: 1 }));
});

test("Kindergerät: freigegebene Aufgaben nur des eigenen Kindes", async () => {
  const db = student().firestore();
  const batches = collection(db, `users/${PARENT}/generated_batches`);
  await assertSucceeds(getDocs(query(batches, where("childId", "==", CHILD))));
  await assertFails(getDocs(batches));
  await assertSucceeds(
    updateDoc(doc(db, `users/${PARENT}/generated_batches/b1/questions/q1`), { status: "answered" }),
  );
  await assertFails(getDoc(doc(db, `users/${PARENT}/generated_batches/b2`)));
  await assertFails(
    updateDoc(doc(db, `users/${PARENT}/generated_batches/b2/questions/q1`), { status: "answered" }),
  );
  await assertFails(deleteDoc(doc(db, `users/${PARENT}/generated_batches/b1`)));
});

test("Gefälschte UID ohne Claims ist kein Kindergerät", async () => {
  // Wer sich (theoretisch) mit einer UID der Form kid:... anmeldet, aber ohne
  // Claims, ist ein gewöhnliches Konto ohne Rechte an fremden Daten.
  const db = env.authenticatedContext(`kid:${PARENT}:${CHILD}`).firestore();
  await assertFails(getDoc(doc(db, `users/${PARENT}/children/${CHILD}`)));
});

test("Kindergerät darf keine Support-Mails anlegen", async () => {
  const db = student().firestore();
  await assertFails(setDoc(doc(db, "mail/m1"), {
    to: ["support@lerndex.de"], userId: `kid:${PARENT}:${CHILD}`,
    message: { subject: "a", text: "0123456789" },
  }));
});

// ── Storage ──────────────────────────────────────────────────────────────────

const jpg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
const meta = { contentType: "image/jpeg" };

test("Storage: Kindergerät lädt nur in den eigenen Ordner hoch", async () => {
  const st = student().storage();
  await assertSucceeds(uploadBytes(ref(st, `tutor_worksheets/${PARENT}/${CHILD}/1.jpg`), jpg, meta));
  await assertFails(uploadBytes(ref(st, `tutor_worksheets/${PARENT}/${SIBLING}/1.jpg`), jpg, meta));
  await assertFails(uploadBytes(ref(st, `task_images/${PARENT}/${CHILD}/1.jpg`), jpg, meta));
  await assertFails(uploadBytes(ref(st, `feedback/${PARENT}/1.jpg`), jpg, meta));
});

test("Storage: Eltern wie bisher", async () => {
  const st = env.authenticatedContext(PARENT).storage();
  await assertSucceeds(uploadBytes(ref(st, `tutor_worksheets/${PARENT}/${CHILD}/2.jpg`), jpg, meta));
  await assertSucceeds(uploadBytes(ref(st, `task_images/${PARENT}/${CHILD}/m/2.jpg`), jpg, meta));
  const other = env.authenticatedContext(OTHER).storage();
  await assertFails(uploadBytes(ref(other, `tutor_worksheets/${PARENT}/${CHILD}/3.jpg`), jpg, meta));
});

// ── Lehrergerät: Aufgaben für Schüler ───────────────────────────────────────

const teacherCtx = (schoolId = "sA") =>
  env.authenticatedContext(`teacher:${schoolId}:t1`, {
    role: "teacher", schoolId, schoolRole: "teacher", teacherId: "t1",
  });

test("Lehrergerät: Aufgaben an Schüler, Fotos hochladen, nur eigene Schule", async () => {
  const db = teacherCtx().firestore();
  const owner = "school_sA";
  await assertSucceeds(setDoc(doc(db, `users/${owner}/generated_batches/b9`), {
    childId: "s1", classId: "4a", assignmentId: "a1",
  }));
  await assertSucceeds(setDoc(doc(db, `users/${owner}/generated_batches/b9/questions/q1`), {
    status: "approved",
  }));
  await assertSucceeds(getDocs(query(collection(db, `users/${owner}/generated_batches`),
    where("classId", "==", "4a"))));
  await assertFails(setDoc(doc(db, `users/school_sB/generated_batches/b1`), { childId: "x" }));
  await assertFails(getDoc(doc(db, `users/${PARENT}/generated_batches/b1`)));

  // Schüler sieht nur den eigenen Batch
  const kid = student("s1", owner).firestore();
  await assertSucceeds(getDoc(doc(kid, `users/${owner}/generated_batches/b9/questions/q1`)));
  const other = student("s2", owner).firestore();
  await assertFails(getDoc(doc(other, `users/${owner}/generated_batches/b9`)));

  const st = teacherCtx().storage();
  await assertSucceeds(uploadBytes(ref(st, `task_images/${owner}/4a/m/1.jpg`), jpg, meta));
  await assertFails(uploadBytes(ref(st, `task_images/school_sB/4a/m/1.jpg`), jpg, meta));
  await assertFails(uploadBytes(ref(st, `task_images/${PARENT}/${CHILD}/1.jpg`), jpg, meta));
});
