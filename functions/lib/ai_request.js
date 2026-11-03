// Prüfung und Umbau der KI-Anfragen aus der Web-App (siehe ../ai.js).
const { HttpsError } = require("firebase-functions/v2/https");

const MODEL = "gemini-3.5-flash";
const LOCATION = "europe-west3";
const DAILY_LIMIT = 400;
const MAX_OUTPUT_TOKENS = 16384;
const MAX_CONTENTS = 80;
const MAX_PARTS = 8;
const MAX_TEXT = 60000;
const MAX_IMAGE_BASE64 = 7 * 1024 * 1024;
const MAX_REQUEST = 9 * 1024 * 1024;
const IMAGE_TYPES = ["image/png", "image/jpeg", "image/webp", "image/heic", "image/heif"];
const THINKING_LEVELS = ["MINIMAL", "LOW", "MEDIUM", "HIGH"];

// Wie kidSafetySettings() in lib/src/ai/vertex_ai_service.dart:
// Sexuelles und Gefährliches streng, Belästigung und Hassrede mittel.
const SAFETY_SETTINGS = [
  { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_MEDIUM_AND_ABOVE", method: "SEVERITY" },
  { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_MEDIUM_AND_ABOVE", method: "SEVERITY" },
  { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_LOW_AND_ABOVE", method: "SEVERITY" },
  { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_LOW_AND_ABOVE", method: "SEVERITY" },
];

const bad = (what) => new HttpsError("invalid-argument", `Ungültige KI-Anfrage: ${what}.`);

function cleanPart(part) {
  if (!part || typeof part !== "object") throw bad("Teil");
  if (typeof part.text === "string") {
    if (part.text.length > MAX_TEXT) throw bad("Text zu lang");
    return { text: part.text };
  }
  const inline = part.inlineData;
  if (inline && typeof inline === "object") {
    if (!IMAGE_TYPES.includes(inline.mimeType)) throw bad("nur Bilder erlaubt");
    if (typeof inline.data !== "string" || inline.data.length > MAX_IMAGE_BASE64) {
      throw bad("Bild zu groß");
    }
    return { inlineData: { mimeType: inline.mimeType, data: inline.data } };
  }
  throw bad("nur Text und Bilder erlaubt");
}

function cleanContent(content, allowedRoles) {
  if (!content || typeof content !== "object") throw bad("Inhalt");
  const role = content.role || "user";
  if (!allowedRoles.includes(role)) throw bad("Rolle");
  if (!Array.isArray(content.parts) || content.parts.length === 0 || content.parts.length > MAX_PARTS) {
    throw bad("Teile");
  }
  return { role, parts: content.parts.map(cleanPart) };
}

function cleanConfig(config) {
  const c = config && typeof config === "object" ? config : {};
  const out = {};
  const max = Number.isInteger(c.maxOutputTokens) ? c.maxOutputTokens : 4096;
  out.maxOutputTokens = Math.max(1, Math.min(max, MAX_OUTPUT_TOKENS));
  if (c.responseMimeType !== undefined) {
    if (!["application/json", "text/plain"].includes(c.responseMimeType)) throw bad("Antwortformat");
    out.responseMimeType = c.responseMimeType;
  }
  if (c.responseSchema !== undefined) {
    if (typeof c.responseSchema !== "object" || JSON.stringify(c.responseSchema).length > 20000) {
      throw bad("Schema");
    }
    out.responseSchema = c.responseSchema;
  }
  const level = c.thinkingConfig?.thinkingLevel;
  out.thinkingConfig = { thinkingLevel: THINKING_LEVELS.includes(level) ? level : "LOW" };
  return out;
}

/** Baut aus der Client-Anfrage die Anfrage an Vertex AI (nur Erlaubtes). */
function buildRequest(data) {
  if (!data || typeof data !== "object") throw bad("leer");
  if (JSON.stringify(data).length > MAX_REQUEST) throw bad("zu groß");
  const { contents, systemInstruction, generationConfig } = data;
  if (!Array.isArray(contents) || contents.length === 0 || contents.length > MAX_CONTENTS) {
    throw bad("Verlauf");
  }
  const request = {
    contents: contents.map((c) => cleanContent(c, ["user", "model"])),
    generationConfig: cleanConfig(generationConfig),
    safetySettings: SAFETY_SETTINGS,
  };
  if (systemInstruction !== undefined && systemInstruction !== null) {
    const sys = cleanContent(systemInstruction, ["system", "user"]);
    if (sys.parts.some((p) => !("text" in p))) throw bad("Systemanweisung");
    request.systemInstruction = { parts: sys.parts };
  }
  return request;
}

/** Antworttext ohne Denk-Teile, wie response.text in firebase_ai. */
function extractResult(response) {
  const candidate = response.candidates?.[0];
  const text = (candidate?.content?.parts || [])
    .filter((p) => typeof p.text === "string" && !p.thought)
    .map((p) => p.text)
    .join("");
  return {
    text: text || null,
    finishReason: candidate?.finishReason || null,
    blockReason: response.promptFeedback?.blockReason || null,
    thoughtsTokens: response.usageMetadata?.thoughtsTokenCount ?? null,
    totalTokens: response.usageMetadata?.totalTokenCount ?? null,
  };
}

module.exports = { buildRequest, extractResult, MODEL, LOCATION, DAILY_LIMIT };
