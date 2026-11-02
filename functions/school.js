// Schule: Lehrkräfte, Klassen, Schülerkarten.
//
// Schüler einer Schule liegen wie Kinder einer Familie unter
// users/school_<schoolId>/children/{studentId}. So funktioniert der ganze
// App-Code (Quiz, Lexi, XP, Belohnungen) für Schüler ohne Umbau.
//
// - Lehrkräfte sind normale Konten (oft auch Eltern) mit den zusätzlichen
//   Claims { schoolId, schoolRole: "admin" | "teacher" }. Alle Lehrkräfte
//   sehen alle Klassen ihrer Schule.
// - Schülergeräte melden sich mit einer QR-Karte an (Link …/s/TOKEN) und
//   bekommen dieselben Claims wie ein gekoppeltes Kindergerät:
//   { role: "student", parentUid: "school_<id>", childId, schoolId }.
//   Karten sind wiederverwendbar (geteilte Schul-Tablets), bis die Lehrkraft
//   neue druckt. Gespeichert wird nur der Hash des Tokens
//   (studentCards/{sha256}), nur Functions haben Zugriff.
// - Schulen legt niemand selbst an: Lerndex erzeugt einen Einladungscode
//   (schoolSignups/{code}, tool/admin/schule.py), die Schule registriert sich
//   über den Link …/schule/CODE. Die Lizenz (schoolLicenseUntil am Dokument
//   users/school_<id>) kommt aus dem Code oder wird von Lerndex gesetzt.
// - Konten ohne eigene Kinder, die über einen Schul- oder Lehrerlink kommen,
//   sind reine Schulkonten (users/{uid}.accountType = "school"): Die App
//   zeigt ihnen nur den Schulbereich.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { db, auth } = require("./lib/firebase");
const { redeemOnce } = require("./lib/claim");
const {
  kidUid,
  normalizeCode,
  newPairingCode,
  newCardToken,
  sha256Hex,
  schoolOwnerUid,
} = require("./lib/helpers");

const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_STUDENTS_PER_CALL = 60;

function requireSignedIn(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Bitte zuerst anmelden.");
  }
  if (request.auth.token.role === "student") {
    throw new HttpsError("permission-denied", "Nicht für Schülergeräte.");
  }
  return request.auth.uid;
}

/** Lehrkraft oder Schul-Admin; gibt die schoolId aus dem Token zurück. */
function requireTeacher(request, { admin = false } = {}) {
  requireSignedIn(request);
  const { schoolId, schoolRole } = request.auth.token;
  if (!schoolId || !["admin", "teacher"].includes(schoolRole)) {
    throw new HttpsError("permission-denied", "Nur für Lehrkräfte.");
  }
  if (admin && schoolRole !== "admin") {
    throw new HttpsError("permission-denied", "Nur für die Schulleitung.");
  }
  return schoolId;
}

/** Schul-Claims ergänzen, ohne andere Claims zu verlieren. */
async function setSchoolClaims(uid, schoolId, schoolRole) {
  const user = await auth.getUser(uid);
  await auth.setCustomUserClaims(uid, {
    ...(user.customClaims || {}),
    schoolId,
    schoolRole,
  });
}

async function requireNoSchool(uid) {
  const user = await auth.getUser(uid);
  if (user.customClaims?.schoolId) {
    throw new HttpsError(
      "already-exists",
      "Dieses Konto gehört schon zu einer Schule.",
    );
  }
  return user;
}

// ── Schule anlegen, Lehrkräfte einladen ──────────────────────────────────────

/**
 * Reines Schulkonto? Nur wenn das Konto keine eigenen Kinder hat – eine
 * Lehrerin, die mit ihrem Elternkonto beitritt, behält ihren Elternbereich.
 * Schulkonten sehen in der App nur den Schulbereich (accountType "school").
 */
async function markSchoolAccount(uid, user, schoolId) {
  const kids = await db.collection(`users/${uid}/children`).limit(1).get();
  if (!kids.empty) return false;
  await db.doc(`users/${uid}`).set(
    {
      accountType: "school",
      schoolId,
      email: user.email || "",
      displayName: user.displayName || "",
      onboardingCompleted: true,
    },
    { merge: true },
  );
  return true;
}

/**
 * Schule anlegen – nur mit einem Einladungscode von Lerndex
 * (schoolSignups/{code}, angelegt mit tool/admin/schule.py). Wer sie anlegt,
 * wird Schul-Admin. Die Lizenz kommt aus dem Code (licenseUntil).
 */
exports.createSchool = onCall(async (request) => {
  const uid = requireSignedIn(request);
  const code = normalizeCode(request.data?.code);
  const invalid = new HttpsError(
    "not-found",
    "Der Einladungslink stimmt nicht oder ist abgelaufen. Bitte melden Sie sich bei Lerndex.",
  );
  if (!code) throw invalid;
  const rawName = request.data?.name;
  const name = typeof rawName === "string" ? rawName.trim() : "";
  if (name.length > 100) {
    throw new HttpsError("invalid-argument", "Der Name der Schule ist zu lang.");
  }
  const user = await requireNoSchool(uid);

  const result = await redeemOnce(db.doc(`schoolSignups/${code}`), async (signup) => {
    const schoolName = name || (signup.schoolName || "").trim();
    if (schoolName.length < 3) {
      throw new HttpsError("invalid-argument", "Bitte den Namen der Schule angeben.");
    }
    const schoolRef = db.collection("schools").doc();
    const schoolId = schoolRef.id;
    const batch = db.batch();
    batch.set(schoolRef, {
      name: schoolName,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: uid,
      signupCode: code,
    });
    batch.set(schoolRef.collection("members").doc(uid), {
      role: "admin",
      name: user.displayName || "",
      email: user.email || "",
      joinedAt: FieldValue.serverTimestamp(),
    });
    // „Besitzer-Konto“ der Schüler (wie users/{uid} bei Eltern)
    batch.set(db.doc(`users/${schoolOwnerUid(schoolId)}`), {
      isSchool: true,
      schoolId,
      displayName: schoolName,
      onboardingCompleted: true,
      createdAt: FieldValue.serverTimestamp(),
      ...(signup.licenseUntil ? { schoolLicenseUntil: signup.licenseUntil } : {}),
    });
    await batch.commit();
    await setSchoolClaims(uid, schoolId, "admin");
    const schoolAccount = await markSchoolAccount(uid, user, schoolId);
    return { schoolId, schoolName, schoolAccount };
  });
  if (!result) throw invalid;
  return result;
});

/** Schul-Admin: Einladungscode für eine Lehrkraft (7 Tage, einmalig). */
exports.createTeacherInvite = onCall(async (request) => {
  const schoolId = requireTeacher(request, { admin: true });
  const code = newPairingCode();
  const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_TTL_MS);
  await db.doc(`schoolInvites/${code}`).set({
    schoolId,
    createdBy: request.auth.uid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
  });
  return { code, expiresAt: expiresAt.toDate().toISOString() };
});

/** Lehrkraft: mit dem Einladungscode der Schule beitreten. */
exports.joinSchool = onCall(async (request) => {
  const uid = requireSignedIn(request);
  const code = normalizeCode(request.data?.code);
  const invalid = new HttpsError(
    "not-found",
    "Der Einladungscode stimmt nicht oder ist abgelaufen.",
  );
  if (!code) throw invalid;
  const user = await requireNoSchool(uid);

  const result = await redeemOnce(db.doc(`schoolInvites/${code}`), async (invite) => {
    const { schoolId } = invite;
    const school = await db.doc(`schools/${schoolId}`).get();
    if (!school.exists) return null;
    await setSchoolClaims(uid, schoolId, "teacher");
    await db.doc(`schools/${schoolId}/members/${uid}`).set({
      role: "teacher",
      name: user.displayName || "",
      email: user.email || "",
      joinedAt: FieldValue.serverTimestamp(),
    });
    // Neues Konto über den Einladungslink: reines Schulkonto
    const schoolAccount = request.data?.schoolAccount === true &&
      (await markSchoolAccount(uid, user, schoolId));
    return { schoolId, schoolName: school.get("name"), schoolAccount };
  });
  if (!result) throw invalid;
  return result;
});

/** Schul-Admin: Lehrkraft aus der Schule entfernen. */
exports.removeTeacher = onCall(async (request) => {
  const schoolId = requireTeacher(request, { admin: true });
  const uid = request.data?.uid;
  if (typeof uid !== "string" || uid === request.auth.uid) {
    throw new HttpsError("invalid-argument", "Diese Lehrkraft geht nicht.");
  }
  const member = await db.doc(`schools/${schoolId}/members/${uid}`).get();
  if (!member.exists) throw new HttpsError("not-found", "Lehrkraft nicht gefunden.");

  await member.ref.delete();
  const user = await auth.getUser(uid);
  const { schoolId: _s, schoolRole: _r, ...rest } = user.customClaims || {};
  await auth.setCustomUserClaims(uid, rest);
  await auth.revokeRefreshTokens(uid);
  return { removed: true };
});

// ── Schülerkarten ────────────────────────────────────────────────────────────

/**
 * Lehrkraft: QR-Karten für Schüler erzeugen. Alte Karten dieser Schüler
 * werden ungültig. Die Tokens gibt es nur in dieser Antwort – gespeichert
 * wird nur ihr Hash.
 */
exports.createStudentCards = onCall(async (request) => {
  const schoolId = requireTeacher(request);
  const studentIds = request.data?.studentIds;
  if (
    !Array.isArray(studentIds) ||
    studentIds.length === 0 ||
    studentIds.length > MAX_STUDENTS_PER_CALL ||
    !studentIds.every((id) => typeof id === "string" && id.length > 0 && id.length < 128)
  ) {
    throw new HttpsError("invalid-argument", "Schülerliste fehlt oder ist zu lang.");
  }

  const owner = schoolOwnerUid(schoolId);
  const students = await Promise.all(
    studentIds.map((id) => db.doc(`users/${owner}/children/${id}`).get()),
  );
  if (students.some((s) => !s.exists)) {
    throw new HttpsError("not-found", "Schüler nicht gefunden.");
  }

  const cardsRef = db.collection("studentCards");
  const old = await Promise.all(
    studentIds.map((id) =>
      cardsRef.where("schoolId", "==", schoolId).where("studentId", "==", id).get(),
    ),
  );
  const batch = db.batch();
  old.forEach((snap) => snap.docs.forEach((doc) => batch.delete(doc.ref)));

  const cards = studentIds.map((studentId) => {
    const token = newCardToken();
    batch.set(cardsRef.doc(sha256Hex(token)), {
      schoolId,
      studentId,
      createdBy: request.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { studentId, token };
  });
  await batch.commit();
  return { cards };
});

/**
 * Schülergerät: QR-Karte einlösen. Ohne Anmeldung aufrufbar, wiederholt
 * nutzbar. Liefert ein Custom Token für das Schülerkonto.
 */
exports.redeemStudentCard = onCall(async (request) => {
  const token = request.data?.token;
  const invalid = new HttpsError(
    "not-found",
    "Diese Karte gilt nicht mehr. Bitte frag deine Lehrerin oder deinen Lehrer.",
  );
  if (typeof token !== "string" || token.length < 16 || token.length > 64) {
    throw invalid;
  }

  const card = await db.doc(`studentCards/${sha256Hex(token)}`).get();
  if (!card.exists) throw invalid;
  const { schoolId, studentId } = card.data();

  const owner = schoolOwnerUid(schoolId);
  const student = await db.doc(`users/${owner}/children/${studentId}`).get();
  if (!student.exists) throw invalid;

  const uid = kidUid(owner, studentId);
  const claims = { role: "student", parentUid: owner, childId: studentId, schoolId };
  try {
    await auth.getUser(uid);
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
    await auth.createUser({ uid });
  }
  await auth.setCustomUserClaims(uid, claims);

  const customToken = await auth.createCustomToken(uid, claims);
  return { token: customToken, childName: student.get("name") || "" };
});

/** Karten eines Schülers löschen und sein Gerätekonto entfernen. */
async function revokeCardsAndAccount(schoolId, studentId) {
  const cards = await db
    .collection("studentCards")
    .where("schoolId", "==", schoolId)
    .where("studentId", "==", studentId)
    .get();
  const batch = db.batch();
  cards.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  const uid = kidUid(schoolOwnerUid(schoolId), studentId);
  try {
    await auth.revokeRefreshTokens(uid);
    await auth.deleteUser(uid);
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
  }
  return cards.size;
}

/**
 * Lehrkraft: Karten eines Schülers ungültig machen und sein Gerätekonto
 * löschen – vor dem Löschen des Schülers oder wenn eine Karte verloren ging.
 */
exports.revokeStudent = onCall(async (request) => {
  const schoolId = requireTeacher(request);
  const studentId = request.data?.studentId;
  if (typeof studentId !== "string" || !studentId) {
    throw new HttpsError("invalid-argument", "studentId fehlt.");
  }
  const revokedCards = await revokeCardsAndAccount(schoolId, studentId);
  return { revokedCards };
});

/**
 * Lehrkraft: Schüler komplett löschen – Karten, Gerätekonto, alle Daten
 * inklusive Lexi-Chats (die Lehrkräfte selbst nicht lesen dürfen) und
 * hochgeladene Aufgabenblätter.
 */
exports.deleteStudent = onCall(async (request) => {
  const schoolId = requireTeacher(request);
  const studentId = request.data?.studentId;
  if (typeof studentId !== "string" || !studentId || studentId.includes("/")) {
    throw new HttpsError("invalid-argument", "studentId fehlt.");
  }
  await revokeCardsAndAccount(schoolId, studentId);

  const owner = schoolOwnerUid(schoolId);
  await db.recursiveDelete(db.doc(`users/${owner}/children/${studentId}`));
  await getStorage()
    .bucket()
    .deleteFiles({ prefix: `tutor_worksheets/${owner}/${studentId}/` });
  return { deleted: true };
});
