// Reine Hilfsfunktionen ohne Firebase – einzeln testbar.

const crypto = require("node:crypto");

/** UID des Kontos für ein gekoppeltes Kindergerät (gleich in lib/.../account.dart). */
function kidUid(parentUid, childId) {
  return `kid:${parentUid}:${childId}`;
}

// Ohne I, O, 0, 1 – die verwechseln Kinder beim Abtippen.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 8;

function newPairingCode() {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  }
  return code;
}

/** "k7mx-q2pa " → "K7MXQ2PA"; null, wenn es kein gültiger Code sein kann. */
function normalizeCode(raw) {
  if (typeof raw !== "string") return null;
  const code = raw.toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (code.length !== CODE_LENGTH) return null;
  for (const ch of code) {
    if (!CODE_ALPHABET.includes(ch)) return null;
  }
  return code;
}

/** base64url mit Padding – wie base64UrlEncode in Dart. */
function base64UrlPadded(buffer) {
  return buffer.toString("base64").replace(/\+/g, "-").replace(/\//g, "_");
}

const PIN_ITERATIONS = 10000;

/** Gleiches Schema wie ParentPin.hashPinSecure in der App. */
function hashPin(pin, salt) {
  let digest = crypto.createHash("sha256").update(`${salt}:${pin}`, "utf8").digest();
  for (let i = 1; i < PIN_ITERATIONS; i++) {
    digest = crypto.createHash("sha256").update(digest).digest();
  }
  return base64UrlPadded(digest);
}

/** Altes, unsicheres Schema (ParentPin.legacyHashPin) – nur für die Migration. */
function legacyHashPin(pin) {
  let hash = 0;
  for (let i = 0; i < pin.length; i++) {
    hash = ((hash << 5) - hash + pin.charCodeAt(i)) | 0;
  }
  return Math.abs(hash).toString();
}

const MAX_LOCKOUT_MS = 24 * 60 * 60 * 1000;

/**
 * Sperrdauer nach der n-ten PIN-Sperre in Folge: base, 2×, 4×, … höchstens
 * 24 h. Mit fester Sperre wäre ein 4-stelliger PIN in wenigen Tagen
 * durchprobiert.
 */
function lockoutMs(lockouts, base) {
  return Math.min(base * 2 ** Math.max(0, lockouts - 1), MAX_LOCKOUT_MS);
}

function newSalt() {
  return base64UrlPadded(crypto.randomBytes(16));
}

/** Token für eine Schüler-QR-Karte (20 Zeichen, ~100 Bit). */
function newCardToken() {
  let token = "";
  for (let i = 0; i < 20; i++) {
    token += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  }
  return token;
}

function sha256Hex(value) {
  return crypto.createHash("sha256").update(value, "utf8").digest("hex");
}

/**
 * „Besitzer-Konto“ der Schüler einer Schule: users/school_<id>, analog zu
 * users/{uid} bei Eltern (gleich in lib/.../account.dart).
 */
function schoolOwnerUid(schoolId) {
  return `school_${schoolId}`;
}

module.exports = {
  newCardToken,
  sha256Hex,
  schoolOwnerUid,
  kidUid,
  CODE_ALPHABET,
  newPairingCode,
  normalizeCode,
  hashPin,
  legacyHashPin,
  newSalt,
  lockoutMs,
};
