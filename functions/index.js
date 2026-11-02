// Cloud Functions für Lerndex (Region Frankfurt).
//
// 1. Kindergeräte koppeln: Eltern erzeugen einen kurzlebigen Code (als QR oder
//    Link app.lerndex.de/k/CODE), das Kindergerät löst ihn ein und bekommt ein
//    eigenes Konto "kid:<parentUid>:<childId>" mit den Claims
//    { role: "student", parentUid, childId }. Die Firestore-/Storage-Rules
//    erlauben diesem Konto nur das eigene Kind.
// 2. Eltern-PIN serverseitig: Hash und Fehlversuche liegen in
//    users/{uid}/private/pin, das kein Client lesen kann. Vorher lag der Hash
//    im users-Dokument – ein Kindergerät, das dieses Dokument lesen darf
//    (Abo-Status), hätte den PIN offline durchprobieren können.
// 3. Schule (school.js): Lehrkräfte, Schülerkarten.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const functionsV1 = require("firebase-functions/v1");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const crypto = require("node:crypto");
const { db, auth } = require("./lib/firebase");
const { redeemOnce } = require("./lib/claim");

const {
  kidUid,
  normalizeCode,
  newPairingCode,
  hashPin,
  legacyHashPin,
  newSalt,
} = require("./lib/helpers");

// ── Hilfen ───────────────────────────────────────────────────────────────────

/**
 * Nur Eltern-Konten, kein Kinder-/Schülergerät. Lehrkräfte sind normale
 * Konten mit zusätzlichen Schul-Claims und dürfen hier ebenfalls (die
 * Lehrerin ist oft selbst Mutter).
 */
function requireParent(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Bitte zuerst anmelden.");
  }
  // Kinder-, Schüler- und Lehrergeräte (role-Claim) sind keine Eltern
  if (request.auth.token.role) {
    throw new HttpsError("permission-denied", "Nur für Eltern.");
  }
  return request.auth.uid;
}

function requireString(value, name, maxLength = 128) {
  if (typeof value !== "string" || value.length === 0 || value.length > maxLength) {
    throw new HttpsError("invalid-argument", `${name} fehlt oder ist ungültig.`);
  }
  return value;
}

async function requireChild(parentUid, childId) {
  const child = await db.doc(`users/${parentUid}/children/${childId}`).get();
  if (!child.exists) {
    throw new HttpsError("not-found", "Kind nicht gefunden.");
  }
  return child;
}

// ── 1. Kindergeräte koppeln ──────────────────────────────────────────────────

const CODE_TTL_MS = 15 * 60 * 1000;

/**
 * Eltern: Kopplungscode für ein Kind erzeugen (15 Minuten gültig, einmalig).
 * Ältere, noch offene Codes für dasselbe Kind werden ungültig.
 */
exports.createPairingCode = onCall(async (request) => {
  const parentUid = requireParent(request);
  const childId = requireString(request.data?.childId, "childId");
  await requireChild(parentUid, childId);

  const old = await db
    .collection("pairingCodes")
    .where("parentUid", "==", parentUid)
    .where("childId", "==", childId)
    .get();
  const batch = db.batch();
  old.docs.forEach((doc) => batch.delete(doc.ref));

  const code = newPairingCode();
  const expiresAt = Timestamp.fromMillis(Date.now() + CODE_TTL_MS);
  batch.set(db.doc(`pairingCodes/${code}`), {
    parentUid,
    childId,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
  });
  await batch.commit();

  return { code, expiresAt: expiresAt.toDate().toISOString() };
});

/**
 * Kindergerät: Code einlösen. Ohne Anmeldung aufrufbar. Liefert ein Custom
 * Token, mit dem sich das Gerät als Kind anmeldet.
 */
exports.redeemPairingCode = onCall(async (request) => {
  const code = normalizeCode(request.data?.code);
  const invalid = new HttpsError(
    "not-found",
    "Der Code stimmt nicht oder ist abgelaufen. Bitte einen neuen Code erzeugen.",
  );
  if (!code) throw invalid;

  const result = await redeemOnce(db.doc(`pairingCodes/${code}`), async (pairing) => {
    const { parentUid, childId } = pairing;
    const child = await db.doc(`users/${parentUid}/children/${childId}`).get();
    if (!child.exists) return null;
    const childName = child.get("name") || "";

    const uid = kidUid(parentUid, childId);
    const claims = { role: "student", parentUid, childId };
    try {
      await auth.getUser(uid);
    } catch (e) {
      if (e.code !== "auth/user-not-found") throw e;
      // Bewusst ohne Namen: das Konto trägt nur die (pseudonymen) IDs
      await auth.createUser({ uid });
    }
    // Claims am Konto speichern, damit sie auch nach dem Token-Refresh gelten
    await auth.setCustomUserClaims(uid, claims);
    const token = await auth.createCustomToken(uid, claims);

    // Für die Elternansicht („Verbundene Geräte“). Bewusst nur der Zeitpunkt.
    const device = await db
      .collection(`users/${parentUid}/children/${childId}/devices`)
      .add({ pairedAt: FieldValue.serverTimestamp() });
    // Die Geräte-ID merkt sich das Gerät, damit es sich später (mit Eltern-PIN)
    // selbst wieder austragen kann (leaveChildDevice).
    return { token, childName, deviceId: device.id };
  });
  if (!result) throw invalid;
  return result;
});

/**
 * Eltern: alle gekoppelten Geräte eines Kindes abmelden. Das Kinderkonto wird
 * gelöscht; bereits ausgestellte Tokens laufen spätestens nach einer Stunde
 * ab. Neu koppeln geht jederzeit mit einem neuen Code (legt das Konto neu an).
 */
exports.unpairChildDevices = onCall(async (request) => {
  const parentUid = requireParent(request);
  const childId = requireString(request.data?.childId, "childId");

  const uid = kidUid(parentUid, childId);
  try {
    await auth.revokeRefreshTokens(uid);
    await auth.deleteUser(uid);
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
  }

  const devices = await db
    .collection(`users/${parentUid}/children/${childId}/devices`)
    .get();
  const batch = db.batch();
  devices.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  return { unpaired: devices.size };
});

/**
 * Kindergerät zu Hause: mit dem Eltern-PIN dieses eine Gerät abmelden (z.B.
 * wenn Eltern am Kinderhandy stehen). Antwort { ok }. Bei ok meldet sich das
 * Gerät selbst ab; das Kinderkonto bleibt, andere Geräte des Kindes bleiben
 * gekoppelt. Schulgeräte brauchen das nicht, dort gibt es Abmelden ohne PIN.
 */
exports.leaveChildDevice = onCall(async (request) => {
  const token = request.auth?.token;
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Bitte zuerst anmelden.");
  }
  if (token.role !== "student" || !token.parentUid || !token.childId ||
      token.parentUid.startsWith("school_")) {
    throw new HttpsError("permission-denied", "Nur für Kindergeräte.");
  }
  const { parentUid, childId } = token;

  const pin = request.data?.pin;
  if (typeof pin !== "string" || !PIN_PATTERN.test(pin)) return { ok: false };
  const { ok, pinSet } = await checkPin(parentUid, pin);
  if (!pinSet) {
    throw new HttpsError(
      "failed-precondition",
      "Es ist noch kein Eltern-PIN festgelegt.",
    );
  }
  if (!ok) return { ok: false };

  const deviceId = request.data?.deviceId;
  if (typeof deviceId === "string" && /^[A-Za-z0-9]{1,64}$/.test(deviceId)) {
    await db.doc(`users/${parentUid}/children/${childId}/devices/${deviceId}`).delete();
  }
  return { ok: true };
});

// ── 2. Eltern-PIN ────────────────────────────────────────────────────────────

const PIN_PATTERN = /^\d{4,6}$/;
const MAX_FAILED_ATTEMPTS = 5;
const LOCKOUT_MS = 5 * 60 * 1000;
// Wer sich gerade neu angemeldet hat, darf den PIN ohne alten PIN neu setzen
// (Grundlage für „PIN vergessen“).
const RECENT_LOGIN_S = 5 * 60;

// ÜBERGANG: Die Play-Store-App bis 1.1.5 kennt den PIN nur über
// users/{uid}.hashedPin. Fehlt das Feld, bietet sie „PIN einrichten“ an – ein
// Kind könnte dort einen eigenen PIN setzen. Deshalb schreiben wir den PIN
// zusätzlich im alten Format (gleiches Verfahren, gleicher Salt), bis alle
// Android-Nutzer auf der neuen Version sind. Preis: Das users-Dokument ist
// für gekoppelte Kindergeräte lesbar, der Hash wäre offline durchprobierbar.
// Danach auf false setzen (und die Übergangsregel in firestore.rules
// entfernen) – der nächste PIN-Vorgang räumt die alten Felder dann weg.
const LEGACY_PIN_MIRROR = true;

const LEGACY_PIN_FIELDS = [
  "hashedPin",
  "pinSalt",
  "pinCreatedAt",
  "pinLastUsed",
  "pinFailedAttempts",
  "pinLockedUntil",
];

/**
 * Liest den gespeicherten PIN – aus private/pin oder noch aus den alten
 * Feldern im users-Dokument (vor der Migration).
 */
async function loadPin(uid) {
  const [privateSnap, userSnap] = await Promise.all([
    db.doc(`users/${uid}/private/pin`).get(),
    db.doc(`users/${uid}`).get(),
  ]);
  const data = userSnap.data() || {};
  // Hat die alte App den PIN inzwischen geändert, steht im users-Dokument
  // ein anderer Hash als in private/pin – dann gilt der neuere aus der alten App.
  const changedByOldApp = data.hashedPin && data.hashedPin !== privateSnap.get("hash");
  if (privateSnap.exists && !changedByOldApp) {
    return { ...privateSnap.data(), legacy: false };
  }
  if (!data.hashedPin) return null;
  return {
    hash: data.hashedPin,
    salt: data.pinSalt || null,
    failedAttempts: data.pinFailedAttempts || 0,
    lockedUntil: data.pinLockedUntil || null,
    legacy: true,
  };
}

function pinMatches(stored, pin) {
  const expected = stored.salt ? hashPin(pin, stored.salt) : legacyHashPin(pin);
  const a = Buffer.from(expected);
  const b = Buffer.from(stored.hash);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** Speichert einen neuen PIN in private/pin (und während des Übergangs im alten Format). */
async function storePin(uid, pin) {
  const salt = newSalt();
  const hash = hashPin(pin, salt);
  const batch = db.batch();
  batch.set(db.doc(`users/${uid}/private/pin`), {
    hash,
    salt,
    failedAttempts: 0,
    lockedUntil: null,
    createdAt: FieldValue.serverTimestamp(),
  });
  const userFields = { pinSet: true };
  if (LEGACY_PIN_MIRROR) {
    userFields.hashedPin = hash;
    userFields.pinSalt = salt;
    userFields.pinFailedAttempts = 0;
    userFields.pinLockedUntil = FieldValue.delete();
  } else {
    for (const f of LEGACY_PIN_FIELDS) userFields[f] = FieldValue.delete();
  }
  batch.set(db.doc(`users/${uid}`), userFields, { merge: true });
  await batch.commit();
}

/**
 * Prüft den PIN mit Sperre nach zu vielen Fehlversuchen. Wirft
 * resource-exhausted (details.retryAfterSeconds), solange gesperrt.
 */
async function checkPin(uid, pin) {
  const stored = await loadPin(uid);
  if (!stored) return { ok: false, pinSet: false };

  const lockedUntil = stored.lockedUntil?.toMillis?.() ?? 0;
  if (lockedUntil > Date.now()) {
    throw new HttpsError("resource-exhausted", "PIN gesperrt.", {
      retryAfterSeconds: Math.ceil((lockedUntil - Date.now()) / 1000),
    });
  }

  if (pinMatches(stored, pin)) {
    if (stored.legacy) {
      // Beim ersten Erfolg in private/pin umziehen (mit neuem Salt)
      await storePin(uid, pin);
    } else {
      await db.doc(`users/${uid}/private/pin`).update({
        failedAttempts: 0,
        lockedUntil: null,
        lastUsed: FieldValue.serverTimestamp(),
      });
    }
    return { ok: true, pinSet: true };
  }

  const failed = (stored.failedAttempts || 0) + 1;
  const locked = failed >= MAX_FAILED_ATTEMPTS;
  const update = {
    failedAttempts: locked ? 0 : failed,
    lockedUntil: locked ? Timestamp.fromMillis(Date.now() + LOCKOUT_MS) : null,
  };
  if (stored.legacy) {
    await db.doc(`users/${uid}`).set(
      { pinFailedAttempts: update.failedAttempts, pinLockedUntil: update.lockedUntil },
      { merge: true },
    );
  } else {
    await db.doc(`users/${uid}/private/pin`).update(update);
  }
  return { ok: false, pinSet: true };
}

/** Eltern: PIN prüfen. Antwort { ok }. */
exports.verifyParentPin = onCall(async (request) => {
  const uid = requireParent(request);
  const pin = request.data?.pin;
  if (typeof pin !== "string" || !PIN_PATTERN.test(pin)) return { ok: false };
  const { ok } = await checkPin(uid, pin);
  return { ok };
});

/**
 * Eltern: PIN setzen oder ändern. Ist schon ein PIN gesetzt, braucht es den
 * alten PIN – oder eine Anmeldung, die höchstens 5 Minuten her ist.
 */
exports.setParentPin = onCall(async (request) => {
  const uid = requireParent(request);
  const pin = request.data?.pin;
  if (typeof pin !== "string" || !PIN_PATTERN.test(pin)) {
    throw new HttpsError("invalid-argument", "PIN muss 4-6 Ziffern enthalten!");
  }

  const stored = await loadPin(uid);
  if (stored) {
    const oldPin = request.data?.oldPin;
    const recentLogin =
      Date.now() / 1000 - (request.auth.token.auth_time || 0) < RECENT_LOGIN_S;
    if (typeof oldPin === "string") {
      const { ok } = await checkPin(uid, oldPin);
      if (!ok) throw new HttpsError("permission-denied", "Alter PIN ist falsch.");
    } else if (!recentLogin) {
      throw new HttpsError("permission-denied", "Alter PIN fehlt.");
    }
  }

  await storePin(uid, pin);
  return { ok: true };
});

// ── 3. Aufräumen beim Löschen eines Elternkontos ─────────────────────────────

/**
 * Die App löscht beim Kontolöschen alle Daten, an die sie herankommt. Den PIN
 * (private/pin), offene Kopplungscodes und den Eintrag in der Lehrerliste
 * einer Schule darf sie nicht anfassen – das erledigt dieser Trigger. (Auth-Trigger gibt es nur als 1. Generation.)
 */
exports.cleanupDeletedParent = functionsV1
  .region("europe-west3")
  .auth.user()
  .onDelete(async (user) => {
    if (user.uid.startsWith("kid:") || user.uid.startsWith("teacher:")) return;
    await db.recursiveDelete(db.collection(`users/${user.uid}/private`));
    const codes = await db
      .collection("pairingCodes")
      .where("parentUid", "==", user.uid)
      .get();
    const batch = db.batch();
    codes.docs.forEach((doc) => batch.delete(doc.ref));
    // Lehrkraft: aus der Lehrerliste der Schule austragen
    const schoolId = user.customClaims?.schoolId;
    if (schoolId) batch.delete(db.doc(`schools/${schoolId}/members/${user.uid}`));
    await batch.commit();
  });

// ── 4. Schule ────────────────────────────────────────────────────────────────

Object.assign(exports, require("./school"));
