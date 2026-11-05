// KI-Proxy für die Web-App (functions/ai.js). Starten mit: npm run test:emulator
const test = require("node:test");
const assert = require("node:assert/strict");
const { buildRequest, extractResult, DAILY_LIMIT } = require("../lib/ai_request");

const text = (t, role = "user") => ({ role, parts: [{ text: t }] });

test("KI-Anfrage: nur Text und Bilder, Modell und Jugendschutz vom Server", () => {
  const req = buildRequest({
    contents: [text("Hallo"), text("Hi", "model"),
      { role: "user", parts: [{ text: "Bild?" }, { inlineData: { mimeType: "image/png", data: "AQID" } }] }],
    systemInstruction: { role: "system", parts: [{ text: "Du bist Lexi." }] },
    generationConfig: {
      maxOutputTokens: 999999, responseMimeType: "application/json",
      responseSchema: { type: "OBJECT" }, thinkingConfig: { thinkingLevel: "LOW" },
      temperature: 2, candidateCount: 8,
    },
    model: "gemini-teuer-pro", safetySettings: [{ category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" }],
    tools: [{ googleSearch: {} }],
  });
  assert.equal(req.contents.length, 3);
  assert.deepEqual(req.contents[2].parts[1], { inlineData: { mimeType: "image/png", data: "AQID" } });
  assert.deepEqual(req.systemInstruction, { parts: [{ text: "Du bist Lexi." }] });
  assert.deepEqual(req.generationConfig, {
    maxOutputTokens: 16384, responseMimeType: "application/json",
    responseSchema: { type: "OBJECT" }, thinkingConfig: { thinkingLevel: "LOW" },
  });
  assert.equal(req.model, undefined);
  assert.equal(req.tools, undefined);
  const sexual = req.safetySettings.find((s) => s.category === "HARM_CATEGORY_SEXUALLY_EXPLICIT");
  assert.equal(sexual.threshold, "BLOCK_LOW_AND_ABOVE");
});

test("KI-Anfrage: Unerlaubtes wird abgelehnt", () => {
  const rejects = (data) => assert.throws(() => buildRequest(data), (e) => e.code === "invalid-argument");
  rejects(undefined);
  rejects({ contents: [] });
  rejects({ contents: [text("x", "system")] });
  rejects({ contents: [{ role: "user", parts: [{ fileData: { fileUri: "gs://x" } }] }] });
  rejects({ contents: [{ role: "user", parts: [{ inlineData: { mimeType: "application/pdf", data: "AA" } }] }] });
  rejects({ contents: [{ role: "user", parts: [{ functionCall: { name: "x" } }] }] });
  rejects({ contents: [text("x".repeat(60001))] });
  rejects({ contents: [text("x")], generationConfig: { responseMimeType: "text/x-python" } });
  rejects({ contents: [text("x")], systemInstruction: { parts: [{ inlineData: { mimeType: "image/png", data: "AA" } }] } });
});

test("KI-Antwort: Denk-Teile weg, Abschlussgrund und Tokens", () => {
  const r = extractResult({
    candidates: [{ finishReason: "STOP", content: { parts: [{ text: "gedacht", thought: true }, { text: "Hal" }, { text: "lo" }] } }],
    usageMetadata: { thoughtsTokenCount: 12, totalTokenCount: 40 },
  });
  assert.deepEqual(r, { text: "Hallo", finishReason: "STOP", blockReason: null, thoughtsTokens: 12, totalTokens: 40 });
  assert.equal(extractResult({ promptFeedback: { blockReason: "SAFETY" } }).blockReason, "SAFETY");
  assert.equal(extractResult({ candidates: [{ finishReason: "SAFETY" }] }).text, null);
});

if (process.env.FIRESTORE_EMULATOR_HOST) {
  const { adb, device, parentWithChildren, expectError, closeDevices, adminAuth } = require("./_client");
  test.after(closeDevices);

  test("KI im Emulator: nur angemeldet, mit Tageslimit", async () => {
    await expectError(device().call("aiGenerate", { contents: [text("Hallo")] }), "unauthenticated");
    const parent = await parentWithChildren();
    await adminAuth().updateUser(parent.uid, { emailVerified: true });
    await parent.auth.currentUser.getIdToken(true);
    await adb.doc(`users/${parent.uid}`).set({ subscription: { isActive: true, plan: "solo" } }, { merge: true });
    const r = await parent.call("aiGenerate", { contents: [text("Hallo")] });
    assert.equal(r.text, "Platzhalter: Hallo");
    assert.equal((await adb.doc(`aiUsage/${parent.uid}`).get()).get("count"), 1);
    await expectError(parent.call("aiGenerate", { contents: [] }), "invalid-argument");

    await adb.doc(`aiUsage/${parent.uid}`).set({ day: new Date().toISOString().slice(0, 10), count: DAILY_LIMIT });
    await expectError(parent.call("aiGenerate", { contents: [text("Noch eine")] }), "resource-exhausted");
    // Neuer Tag: Zähler beginnt von vorn
    await adb.doc(`aiUsage/${parent.uid}`).set({ day: "2000-01-01", count: DAILY_LIMIT });
    assert.equal((await parent.call("aiGenerate", { contents: [text("Morgen")] })).text, "Platzhalter: Morgen");
  });
}
