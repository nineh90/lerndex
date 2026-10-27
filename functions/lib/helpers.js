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

function newSalt() {
  return base64UrlPadded(crypto.randomBytes(16));
}

module.exports = {
  kidUid,
  CODE_ALPHABET,
  newPairingCode,
  normalizeCode,
  hashPin,
  legacyHashPin,
  newSalt,
};
