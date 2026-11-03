// Schule: Lehrkräfte, Klassen, Schülerkarten.
//
// Schüler einer Schule liegen wie Kinder einer Familie unter
// users/school_<schoolId>/children/{studentId}. So funktioniert der ganze
// App-Code (Quiz, Lexi, XP, Belohnungen) für Schüler ohne Umbau.
//
// - Die Schulleitung (schoolRole "admin", Konto mit E-Mail) verwaltet nur
//   die Lehrkräfte. Schülerdaten sieht sie nicht.
// - Lehrkräfte melden sich mit QR-Karte + PIN an (Konto
//   "teacher:<schoolId>:<teacherId>", role "teacher", schoolRole "teacher").
//   Alle Lehrkräfte sehen alle Klassen ihrer Schule, legen Klassen und
//   Schüler an und drucken Schülerkarten.
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
  hashPin,
  newSalt,
} = require("./lib/helpers");

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

/**
 * Schul-Konto; gibt die schoolId aus dem Token zurück.
 * admin: nur Schulleitung (verwaltet Lehrkräfte),
 * teacher: nur Lehrkräfte (Klassen, Schüler, Karten). Die Schulleitung sieht
 * bewusst keine Schülerdaten.
 */
function requireTeacher(request, { admin = false, teacher = false } = {}) {
  requireSignedIn(request);
  const { schoolId, schoolRole } = request.auth.token;
  if (!schoolId || !["admin", "teacher"].includes(schoolRole)) {
    throw new HttpsError("permission-denied", "Nur für Lehrkräfte.");
  }
  if (admin && schoolRole !== "admin") {
    throw new HttpsError("permission-denied", "Nur für die Schulleitung.");
  }
  if (teacher && schoolRole !== "teacher") {
    throw new HttpsError("permission-denied", "Nur für Lehrkräfte.");
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

// ── Lehrkräfte: QR-Karte + PIN ──────────────────────────────────────────────
//
// Die Schulleitung legt Lehrkräfte mit Namen an und gibt ihnen eine QR-Karte
// (Link …/l/TOKEN). Beim ersten Scannen legt die Lehrkraft ihre PIN fest,
// danach braucht jede Anmeldung Karte + PIN. Die Karte allein reicht nicht:
// Sie öffnet die Daten aller Schüler der Schule.
// Konto: "teacher:<schoolId>:<teacherId>" mit den Claims
// { role: "teacher", schoolId, schoolRole: "teacher", teacherId }.

const TEACHER_PIN = /^\d{4,6}$/;
const TEACHER_MAX_FAILED = 5;
const TEACHER_LOCK_MS = 15 * 60 * 1000;

function teacherUid(schoolId, teacherId) {
  return `teacher:${schoolId}:${teacherId}`;
}

function teacherPinRef(schoolId, teacherId) {
  return db.doc(`schools/${schoolId}/members/${teacherId}/private/pin`);
}

/** Neue Karte für eine Lehrkraft, alte Karten werden ungültig. */
async function issueTeacherCard(schoolId, teacherId, createdBy) {
  const old = await db
    .collection("teacherCards")
    .where("schoolId", "==", schoolId)
    .where("teacherId", "==", teacherId)
    .get();
  const batch = db.batch();
  old.docs.forEach((doc) => batch.delete(doc.ref));
  const token = newCardToken();
  batch.set(db.doc(`teacherCards/${sha256Hex(token)}`), {
    schoolId,
    teacherId,
    createdBy,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return token;
}

/** Schulleitung: Lehrkraft anlegen. Antwort { teacherId, token }. */
exports.createTeacher = onCall(async (request) => {
  const schoolId = requireTeacher(request, { admin: true });
  const name = typeof request.data?.name === "string" ? request.data.name.trim() : "";
  if (name.length < 2 || name.length > 60) {
    throw new HttpsError("invalid-argument", "Bitte den Namen der Lehrkraft angeben.");
  }
  const member = db.collection(`schools/${schoolId}/members`).doc();
  await member.set({
    role: "teacher",
    login: "card",
    name,
    email: "",
    pinSet: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  const token = await issueTeacherCard(schoolId, member.id, request.auth.uid);
  return { teacherId: member.id, token };
});

/**
 * Schulleitung: neue Karte für eine Lehrkraft (verloren o.ä.). Die alte gilt
 * nicht mehr, angemeldete Geräte werden abgemeldet. resetPin: PIN vergessen –
 * beim nächsten Scannen legt die Lehrkraft eine neue fest.
 */
exports.reissueTeacherCard = onCall(async (request) => {
  const schoolId = requireTeacher(request, { admin: true });
  const teacherId = request.data?.teacherId;
  if (typeof teacherId !== "string" || teacherId.length === 0 || teacherId.length > 64) {
    throw new HttpsError("invalid-argument", "Lehrkraft fehlt.");
  }
  const member = await db.doc(`schools/${schoolId}/members/${teacherId}`).get();
  if (!member.exists || member.get("login") !== "card") {
    throw new HttpsError("not-found", "Lehrkraft nicht gefunden.");
  }
  if (request.data?.resetPin === true) {
    await teacherPinRef(schoolId, teacherId).delete();
    await member.ref.update({ pinSet: false });
  }
  const token = await issueTeacherCard(schoolId, teacherId, request.auth.uid);
  await auth.revokeRefreshTokens(teacherUid(schoolId, teacherId)).catch((e) => {
    if (e.code !== "auth/user-not-found") throw e;
  });
  return { token };
});

/**
 * Lehrergerät: mit Karte und PIN anmelden. Ohne Anmeldung aufrufbar.
 * - nur { token }: Antwort { pinSet } (ob die PIN schon festgelegt ist)
 * - { token, newPin }: erste Anmeldung, PIN festlegen → { token: customToken }
 * - { token, pin }: Anmeldung → { token: customToken } oder { ok: false }
 * Nach 5 falschen PINs ist die Karte 15 Minuten gesperrt (resource-exhausted).
 */
exports.redeemTeacherCard = onCall(async (request) => {
  const cardToken = request.data?.token;
  const invalid = new HttpsError(
    "not-found",
    "Diese Karte gilt nicht mehr. Bitte wenden Sie sich an Ihre Schulleitung.",
  );
  if (typeof cardToken !== "string" || cardToken.length < 16 || cardToken.length > 64) {
    throw invalid;
  }
  const card = await db.doc(`teacherCards/${sha256Hex(cardToken)}`).get();
  if (!card.exists) throw invalid;
  const { schoolId, teacherId } = card.data();
  const member = await db.doc(`schools/${schoolId}/members/${teacherId}`).get();
  if (!member.exists) throw invalid;

  const pinRef = teacherPinRef(schoolId, teacherId);
  const stored = await pinRef.get();
  const { pin, newPin } = request.data || {};

  if (!stored.exists) {
    if (newPin === undefined) return { pinSet: false, name: member.get("name") || "" };
    if (typeof newPin !== "string" || !TEACHER_PIN.test(newPin)) {
      throw new HttpsError("invalid-argument", "Die PIN braucht 4 bis 6 Ziffern.");
    }
    const salt = newSalt();
    // create() statt set(): legen zwei Geräte gleichzeitig eine PIN fest,
    // gewinnt das erste
    await pinRef.create({ hash: hashPin(newPin, salt), salt, failedAttempts: 0, lockedUntil: null })
      .catch(() => {
        throw new HttpsError("already-exists", "Die PIN wurde gerade schon festgelegt.");
      });
    await member.ref.update({ pinSet: true });
  } else {
    if (pin === undefined) return { pinSet: true, name: member.get("name") || "" };
    const data = stored.data();
    const lockedUntil = data.lockedUntil?.toMillis?.() ?? 0;
    if (lockedUntil > Date.now()) {
      throw new HttpsError("resource-exhausted", "Karte gesperrt.", {
        retryAfterSeconds: Math.ceil((lockedUntil - Date.now()) / 1000),
      });
    }
    const ok = typeof pin === "string" && TEACHER_PIN.test(pin) &&
      hashPin(pin, data.salt) === data.hash;
    if (!ok) {
      const failed = (data.failedAttempts || 0) + 1;
      const locked = failed >= TEACHER_MAX_FAILED;
      await pinRef.update({
        failedAttempts: locked ? 0 : failed,
        lockedUntil: locked ? Timestamp.fromMillis(Date.now() + TEACHER_LOCK_MS) : null,
      });
      return { ok: false };
    }
    await pinRef.update({ failedAttempts: 0, lockedUntil: null, lastUsed: FieldValue.serverTimestamp() });
  }

  const uid = teacherUid(schoolId, teacherId);
  const claims = { role: "teacher", schoolId, schoolRole: "teacher", teacherId };
  try {
    await auth.getUser(uid);
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
    await auth.createUser({ uid });
  }
  await auth.setCustomUserClaims(uid, claims);
  const customToken = await auth.createCustomToken(uid, claims);
  return { ok: true, token: customToken, name: member.get("name") || "" };
});

/**
 * Schulleitung: Lehrkraft entfernen. Kartenlehrkräfte: Konto, Karten und PIN
 * werden gelöscht. Lehrkräfte mit eigenem Konto (E-Mail): nur die Schul-
 * Claims fallen weg, das Konto bleibt.
 */
exports.removeTeacher = onCall(async (request) => {
  const schoolId = requireTeacher(request, { admin: true });
  const memberId = request.data?.uid;
  if (typeof memberId !== "string" || memberId.length === 0 || memberId === request.auth.uid) {
    throw new HttpsError("invalid-argument", "Diese Lehrkraft geht nicht.");
  }
  const member = await db.doc(`schools/${schoolId}/members/${memberId}`).get();
  if (!member.exists) throw new HttpsError("not-found", "Lehrkraft nicht gefunden.");

  if (member.get("login") === "card") {
    const uid = teacherUid(schoolId, memberId);
    try {
      await auth.revokeRefreshTokens(uid);
      await auth.deleteUser(uid);
    } catch (e) {
      if (e.code !== "auth/user-not-found") throw e;
    }
    const cards = await db
      .collection("teacherCards")
      .where("schoolId", "==", schoolId)
      .where("teacherId", "==", memberId)
      .get();
    const batch = db.batch();
    cards.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    await db.recursiveDelete(member.ref);
  } else {
    await member.ref.delete();
    const user = await auth.getUser(memberId);
    const { schoolId: _s, schoolRole: _r, ...rest } = user.customClaims || {};
    await auth.setCustomUserClaims(memberId, rest);
    await auth.revokeRefreshTokens(memberId);
  }
  return { removed: true };
});

// ── Schülerkarten ────────────────────────────────────────────────────────────

/**
 * Lehrkraft: QR-Karten für Schüler erzeugen. Alte Karten dieser Schüler
 * werden ungültig. Die Tokens gibt es nur in dieser Antwort – gespeichert
 * wird nur ihr Hash.
 */
exports.createStudentCards = onCall(async (request) => {
  const schoolId = requireTeacher(request, { teacher: true });
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
  // Heimkarten aus dem Elternbrief bleiben gültig
  old.forEach((snap) =>
    snap.docs.filter((doc) => doc.get("kind") !== "home").forEach((doc) => batch.delete(doc.ref)),
  );

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
  const schoolId = requireTeacher(request, { teacher: true });
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
// ── Eltern verbinden (Elternbrief) ───────────────────────────────────────────
//
// Die Lehrkraft druckt pro Kind einen Elternbrief mit zwei QR-Codes:
// - „Eltern verbinden“ (…/e/CODE, parentLinks/{code}): Eltern verbinden ihr
//   Konto mit dem Schulkind. Ihre UID kommt in parentUids am Schülerdokument,
//   die Rules geben ihnen damit Lesezugriff (auch Lexi-Gespräche) und
//   Schreibzugriff auf die Belohnungen. Kostet die Eltern kein Abo.
// - „Zu Hause lernen“: eigene Schülerkarte (kind "home"), die beim Neudruck
//   der Schulkarten gültig bleibt.

const MAX_PARENTS_PER_CHILD = 4;

/** Lehrkraft: Elternbriefe für Schüler (alte Codes/Heimkarten werden ungültig). */
exports.createParentLetters = onCall(async (request) => {
  const schoolId = requireTeacher(request, { teacher: true });
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
  if (students.some((st) => !st.exists)) {
    throw new HttpsError("not-found", "Schüler nicht gefunden.");
  }

  const letters = [];
  for (const studentId of studentIds) {
    const [oldLinks, oldHome] = await Promise.all([
      db.collection("parentLinks").where("schoolId", "==", schoolId)
        .where("studentId", "==", studentId).get(),
      db.collection("studentCards").where("schoolId", "==", schoolId)
        .where("studentId", "==", studentId).where("kind", "==", "home").get(),
    ]);
    const batch = db.batch();
    oldLinks.docs.forEach((doc) => batch.delete(doc.ref));
    oldHome.docs.forEach((doc) => batch.delete(doc.ref));
    const code = newPairingCode();
    batch.set(db.doc(`parentLinks/${code}`), {
      schoolId,
      studentId,
      createdBy: request.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    const homeToken = newCardToken();
    batch.set(db.doc(`studentCards/${sha256Hex(homeToken)}`), {
      schoolId,
      studentId,
      kind: "home",
      createdBy: request.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
    letters.push({ studentId, parentCode: code, homeToken });
  }
  return { letters };
});

/** Eltern: Konto mit einem Schulkind verbinden (Code aus dem Elternbrief). */
exports.linkSchoolChild = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Bitte zuerst anmelden.");
  const token = request.auth.token;
  if (token.role || token.schoolRole === "admin") {
    throw new HttpsError("permission-denied", "Bitte mit einem Elternkonto anmelden.");
  }
  const uid = request.auth.uid;
  const code = normalizeCode(request.data?.code);
  const invalid = new HttpsError(
    "not-found",
    "Der Code stimmt nicht. Bitte prüfen Sie den Elternbrief oder fragen Sie die Lehrkraft.",
  );
  if (!code) throw invalid;
  const link = await db.doc(`parentLinks/${code}`).get();
  if (!link.exists) throw invalid;
  const { schoolId, studentId } = link.data();
  const owner = schoolOwnerUid(schoolId);
  const studentRef = db.doc(`users/${owner}/children/${studentId}`);

  const result = await db.runTransaction(async (tx) => {
    const student = await tx.get(studentRef);
    if (!student.exists) return null;
    const parents = student.get("parentUids") || [];
    if (!parents.includes(uid) && parents.length >= MAX_PARENTS_PER_CHILD) {
      throw new HttpsError("resource-exhausted", "Mit diesem Kind sind schon 4 Konten verbunden.");
    }
    tx.update(studentRef, { parentUids: FieldValue.arrayUnion(uid) });
    return student;
  });
  if (!result) throw invalid;

  const [school, schoolClass] = await Promise.all([
    db.doc(`schools/${schoolId}`).get(),
    db.doc(`schools/${schoolId}/classes/${result.get("classId") || "-"}`).get(),
  ]);
  const info = {
    schoolId,
    studentId,
    ownerUid: owner,
    name: result.get("name") || "",
    schoolName: school.get("name") || "",
    className: schoolClass.exists ? schoolClass.get("name") || "" : "",
  };
  await db.doc(`users/${uid}/linkedChildren/${schoolId}_${studentId}`).set({
    ...info,
    linkedAt: FieldValue.serverTimestamp(),
  });
  return info;
});

/** Eltern: Verbindung zu einem Schulkind trennen. */
exports.unlinkSchoolChild = onCall(async (request) => {
  if (!request.auth || request.auth.token.role) {
    throw new HttpsError("permission-denied", "Nur für Eltern.");
  }
  const uid = request.auth.uid;
  const { schoolId, studentId } = request.data || {};
  if (typeof schoolId !== "string" || typeof studentId !== "string" ||
      !schoolId || !studentId || schoolId.includes("/") || studentId.includes("/")) {
    throw new HttpsError("invalid-argument", "Kind fehlt.");
  }
  await db.doc(`users/${schoolOwnerUid(schoolId)}/children/${studentId}`)
    .update({ parentUids: FieldValue.arrayRemove(uid) })
    .catch(() => {});
  await db.doc(`users/${uid}/linkedChildren/${schoolId}_${studentId}`).delete();
  return { unlinked: true };
});

/** Verbundene Eltern eines Schülers austragen (beim Löschen des Schülers). */
async function unlinkAllParents(schoolId, studentId) {
  const student = await db.doc(`users/${schoolOwnerUid(schoolId)}/children/${studentId}`).get();
  const parents = student.exists ? student.get("parentUids") || [] : [];
  const links = await db.collection("parentLinks").where("schoolId", "==", schoolId)
    .where("studentId", "==", studentId).get();
  const batch = db.batch();
  parents.forEach((uid) =>
    batch.delete(db.doc(`users/${uid}/linkedChildren/${schoolId}_${studentId}`)),
  );
  links.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
}

exports.deleteStudent = onCall(async (request) => {
  const schoolId = requireTeacher(request, { teacher: true });
  const studentId = request.data?.studentId;
  if (typeof studentId !== "string" || !studentId || studentId.includes("/")) {
    throw new HttpsError("invalid-argument", "studentId fehlt.");
  }
  await revokeCardsAndAccount(schoolId, studentId);
  await unlinkAllParents(schoolId, studentId);

  const owner = schoolOwnerUid(schoolId);
  await db.recursiveDelete(db.doc(`users/${owner}/children/${studentId}`));
  await getStorage()
    .bucket()
    .deleteFiles({ prefix: `tutor_worksheets/${owner}/${studentId}/` });
  return { deleted: true };
});
