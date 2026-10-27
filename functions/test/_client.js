// Gemeinsame Helfer für die Emulator-Tests (kein *.test.js, läuft nicht allein).
const assert = require("node:assert/strict");
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


async function closeDevices() {
  for (const app of apps) await deleteApp(app);
}

module.exports = {
  PROJECT, adb, device, parentWithChildren, expectError, closeDevices,
  signInWithCustomToken, signOut, createUserWithEmailAndPassword,
  doc, getDoc, setDoc, Timestamp, adminAuth,
};
