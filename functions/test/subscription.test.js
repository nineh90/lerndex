// Abo-Status vom Server (RevenueCat) und Zugang zur KI.
const test = require("node:test");
const assert = require("node:assert/strict");
const { statusFromSubscriber, planFromProduct } = require("../lib/revenuecat");
const { hasAccess, GRACE_MS } = require("../lib/access");
const { lockoutMs } = require("../lib/helpers");

const DAY = 24 * 60 * 60 * 1000;
const now = new Date("2026-11-05T12:00:00Z");
const ts = (date) => ({ toMillis: () => date.getTime() });

test("RevenueCat: Plan, Laufzeit, Testphase, Zusatzplätze", () => {
  const subscriber = {
    entitlements: { premium: { expires_date: "2026-12-01T00:00:00Z", product_identifier: "lerndex_family:monthly" } },
    subscriptions: { "lerndex_family:monthly": { period_type: "trial" } },
    non_subscriptions: { lerndex_extra_child_slot: [{ id: "a" }, { id: "b" }] },
  };
  const s = statusFromSubscriber(subscriber, now);
  assert.equal(s.plan, "family");
  assert.equal(s.isActive, true);
  assert.equal(s.isTrial, true);
  assert.equal(s.extraChildSlots, 2);
  assert.equal(s.expiresAt.toISOString(), "2026-12-01T00:00:00.000Z");
});

test("RevenueCat: abgelaufen, ohne Abo, unbekanntes Produkt", () => {
  const expired = statusFromSubscriber({
    entitlements: { premium: { expires_date: "2026-10-01T00:00:00Z", product_identifier: "lerndex_duo" } },
  }, now);
  assert.deepEqual([expired.plan, expired.isActive], ["none", false]);
  const none = statusFromSubscriber({ non_subscriptions: { lerndex_extra_child_slot: [{}] } }, now);
  assert.deepEqual([none.plan, none.isActive, none.extraChildSlots], ["none", false, 1]);
  // Wer zahlt, hat Zugang – auch wenn die Produkt-ID kein Stichwort enthält
  assert.equal(planFromProduct("lerndex_monthly"), "solo");
  assert.equal(planFromProduct("lerndex_duo_yearly"), "duo");
});

test("Zugang zur KI: Abo, Kulanz, Lizenz, Testzugang", () => {
  const t = now.getTime();
  assert.equal(hasAccess(undefined, t), false);
  assert.equal(hasAccess({ subscription: { isActive: false } }, t), false);
  assert.equal(hasAccess({ subscription: { isActive: true } }, t), true);
  assert.equal(hasAccess({ subscription: { isActive: true, expiresAt: ts(new Date(t + DAY)) } }, t), true);
  assert.equal(hasAccess({ subscription: { isActive: true, expiresAt: ts(new Date(t - DAY)) } }, t), true);
  assert.equal(hasAccess({ subscription: { isActive: true, expiresAt: ts(new Date(t - GRACE_MS - DAY)) } }, t), false);
  assert.equal(hasAccess({ testAccess: true }, t), true);
  assert.equal(hasAccess({ schoolLicenseUntil: ts(new Date(t + DAY)) }, t), true);
  assert.equal(hasAccess({ schoolLicenseUntil: ts(new Date(t - DAY)) }, t), false);
});

test("PIN-Sperre wird mit jeder Sperre länger, höchstens 24 h", () => {
  const min = 60 * 1000;
  assert.equal(lockoutMs(1, 5 * min), 5 * min);
  assert.equal(lockoutMs(2, 5 * min), 10 * min);
  assert.equal(lockoutMs(4, 5 * min), 40 * min);
  assert.equal(lockoutMs(30, 5 * min), DAY);
});

if (process.env.FIRESTORE_EMULATOR_HOST) {
  const {
    adb, device, parentWithChildren, expectError, closeDevices, adminAuth,
    signInWithCustomToken, Timestamp,
  } = require("./_client");
  const fs = require("node:fs");
  const path = require("node:path");
  test.after(closeDevices);

  const text = (t) => ({ role: "user", parts: [{ text: t }] });

  /** Elternteil mit bestätigter E-Mail (frisches Token). */
  async function verifiedParent(fields = {}) {
    const parent = await parentWithChildren();
    await adminAuth().updateUser(parent.uid, { emailVerified: true });
    await parent.auth.currentUser.getIdToken(true);
    await adb.doc(`users/${parent.uid}`).set(fields, { merge: true });
    return parent;
  }

  test("KI: unbestätigte E-Mail und ohne Abo gesperrt, Kindergerät erlaubt", async () => {
    const unverified = await parentWithChildren();
    await expectError(unverified.call("aiGenerate", { contents: [text("Hallo")] }), "permission-denied");

    const noAbo = await verifiedParent();
    await expectError(noAbo.call("aiGenerate", { contents: [text("Hallo")] }), "permission-denied");
    // Abo selbst eintragen geht nicht mehr (Regeln)
    await assert.rejects(
      require("firebase/firestore").updateDoc(
        require("firebase/firestore").doc(noAbo.db, `users/${noAbo.uid}`),
        { subscription: { plan: "family", isActive: true } },
      ),
    );

    const paying = await verifiedParent({ subscription: { plan: "solo", isActive: true } });
    assert.equal((await paying.call("aiGenerate", { contents: [text("Hallo")] })).text, "Platzhalter: Hallo");

    // Denkstufe HIGH wird auf LOW gedeckelt
    const r = await paying.call("aiGenerate", {
      contents: [text("x")], generationConfig: { thinkingConfig: { thinkingLevel: "HIGH" } },
    });
    assert.equal(r.request.generationConfig.thinkingConfig.thinkingLevel, "LOW");

    const { code } = await paying.call("createPairingCode", { childId: "jan" });
    const kid = device();
    const { token } = await kid.call("redeemPairingCode", { code });
    await signInWithCustomToken(kid.auth, token);
    assert.equal((await kid.call("aiGenerate", { contents: [text("Kind")] })).text, "Platzhalter: Kind");
  });

  test("Abo: syncSubscription schreibt den Status von RevenueCat", async () => {
    const parent = await verifiedParent();
    await adb.doc(`_emulator/revenuecat/subscribers/${parent.uid}`).set({
      entitlements: { premium: { expires_date: "2099-01-01T00:00:00Z", product_identifier: "lerndex_family" } },
      subscriptions: {},
      non_subscriptions: { lerndex_extra_child_slot: [{ id: "x" }] },
    });
    const s = await parent.call("syncSubscription", {});
    assert.equal(s.plan, "family");
    assert.equal(s.extraChildSlots, 1);
    const stored = (await adb.doc(`users/${parent.uid}`).get()).get("subscription");
    assert.equal(stored.isActive, true);
    assert.equal(stored.extraChildSlots, 1);
    assert.ok(stored.expiresAt instanceof Timestamp);
  });

  test("Abo-Webhook: nur mit Geheimnis, gleicht den Kunden ab", async () => {
    const parent = await verifiedParent();
    await adb.doc(`_emulator/revenuecat/subscribers/${parent.uid}`).set({
      entitlements: { premium: { expires_date: "2099-01-01T00:00:00Z", product_identifier: "lerndex_duo" } },
    });
    const emulators = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", "firebase.json"))).emulators;
    const url = `http://127.0.0.1:${emulators.functions.port}/demo-lerndex/europe-west3/revenuecatWebhook`;
    const post = (auth) => fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(auth ? { Authorization: auth } : {}) },
      body: JSON.stringify({ event: { type: "RENEWAL", app_user_id: parent.uid, aliases: ["$RCAnonymousID:abc"] } }),
    });
    assert.equal((await post()).status, 401);
    assert.equal((await post("Bearer falsch")).status, 401);
    assert.equal((await post("Bearer emulator-webhook-geheimnis")).status, 200);
    assert.equal((await adb.doc(`users/${parent.uid}`).get()).get("subscription.plan"), "duo");
  });
}
