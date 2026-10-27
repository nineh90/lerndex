// Gemeinsame Firebase-Initialisierung für alle Function-Dateien.

const { setGlobalOptions } = require("firebase-functions/v2");
const { initializeApp, getApps } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();
setGlobalOptions({ region: "europe-west3", maxInstances: 10 });

module.exports = { db: getFirestore(), auth: getAuth() };
