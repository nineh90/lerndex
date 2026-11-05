// Abo-Status aus RevenueCat, geschrieben nur vom Server.
//
// Vorher schrieb die Android-App den Status selbst nach users/{uid}.subscription.
// Das Feld war damit für jeden Elternteil frei beschreibbar (Abo im Browser
// selbst freischalten), lief nie ab und verlor bei jedem Sync die gekauften
// Zusatz-Kinderplätze. Jetzt:
// - syncSubscription (App, nach Kauf/Wiederherstellen/Start) und der
//   RevenueCat-Webhook holen den Status bei RevenueCat und schreiben ihn.
// - Zusatz-Kinderplätze = Anzahl der Käufe des Produkts lerndex_extra_child_slot.
// - deleteRevenueCatCustomer löscht den Kunden bei RevenueCat, wenn das
//   Elternkonto gelöscht wird (DSGVO).
//
// Einrichtung (einmalig, siehe docs/PLAN-schule-web.md):
//   firebase functions:secrets:set REVENUECAT_SECRET_KEY   (Secret API Key v1, sk_…)
//   firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH (beliebiger langer Wert)
//   RevenueCat → Integrations → Webhooks: URL der Function revenuecatWebhook,
//   Authorization-Header = REVENUECAT_WEBHOOK_AUTH

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const functionsV1 = require("firebase-functions/v1");
const { defineSecret } = require("firebase-functions/params");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const crypto = require("node:crypto");
const { db } = require("./lib/firebase");
const { statusFromSubscriber } = require("./lib/revenuecat");

const RC_KEY = defineSecret("REVENUECAT_SECRET_KEY");
const RC_WEBHOOK_AUTH = defineSecret("REVENUECAT_WEBHOOK_AUTH");
const RC_API = "https://api.revenuecat.com/v1/subscribers/";

async function fetchSubscriber(uid, key) {
  // Im Emulator gibt es kein RevenueCat: Testdaten aus Firestore
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    const fake = await db.doc(`_emulator/revenuecat/subscribers/${uid}`).get();
    return fake.exists ? fake.data() : { entitlements: {}, subscriptions: {}, non_subscriptions: {} };
  }
  const res = await fetch(RC_API + encodeURIComponent(uid), {
    headers: { Authorization: `Bearer ${key}` },
    signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) {
    console.error("RevenueCat", res.status);
    throw new HttpsError("unavailable", "Der Abo-Status ist gerade nicht abrufbar.");
  }
  return (await res.json()).subscriber || {};
}

/** Status bei RevenueCat holen und am Elternkonto speichern. */
async function syncUser(uid, key) {
  const userRef = db.doc(`users/${uid}`);
  const user = await userRef.get();
  if (!user.exists) return null;
  const status = statusFromSubscriber(await fetchSubscriber(uid, key));
  await userRef.update({
    subscription: {
      plan: status.plan,
      isActive: status.isActive,
      isTrial: status.isTrial,
      expiresAt: status.expiresAt ? Timestamp.fromDate(status.expiresAt) : null,
      extraChildSlots: status.extraChildSlots,
      source: "revenuecat",
    },
    subscriptionUpdatedAt: FieldValue.serverTimestamp(),
  });
  return status;
}

/** Eltern: Abo-Status jetzt abgleichen. Antwort wie SubscriptionStatus in der App. */
exports.syncSubscription = onCall({ secrets: [RC_KEY] }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Bitte zuerst anmelden.");
  if (request.auth.token.role) throw new HttpsError("permission-denied", "Nur für Eltern.");
  const status = await syncUser(request.auth.uid, RC_KEY.value());
  if (!status) throw new HttpsError("not-found", "Konto nicht gefunden.");
  return { ...status, expiresAt: status.expiresAt ? status.expiresAt.toISOString() : null };
});

function sameSecret(a, b) {
  const x = Buffer.from(String(a || ""));
  const y = Buffer.from(String(b || ""));
  return x.length > 0 && x.length === y.length && crypto.timingSafeEqual(x, y);
}

/** RevenueCat meldet Käufe, Verlängerungen, Kündigungen, Abläufe. */
exports.revenuecatWebhook = onRequest(
  { secrets: [RC_KEY, RC_WEBHOOK_AUTH] },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("");
      return;
    }
    const auth = (req.get("authorization") || "").replace(/^Bearer\s+/i, "");
    if (!sameSecret(auth, RC_WEBHOOK_AUTH.value())) {
      res.status(401).send("");
      return;
    }
    const event = req.body?.event || {};
    const ids = new Set(
      [event.app_user_id, event.original_app_user_id, ...(event.aliases || []),
        ...(event.transferred_to || [])]
        .filter((id) => typeof id === "string" && id && !id.startsWith("$RCAnonymousID")
          && !id.includes("/") && id.length <= 128),
    );
    try {
      for (const uid of ids) await syncUser(uid, RC_KEY.value());
      res.status(200).send("ok");
    } catch (e) {
      console.error("RevenueCat-Webhook", e.message);
      // 5xx: RevenueCat versucht es später erneut
      res.status(503).send("");
    }
  },
);

/** Elternkonto gelöscht: Kunde bei RevenueCat löschen (Kaufhistorie, UID). */
exports.deleteRevenueCatCustomer = functionsV1
  .runWith({ secrets: ["REVENUECAT_SECRET_KEY"] })
  .region("europe-west3")
  .auth.user()
  .onDelete(async (user) => {
    if (user.uid.includes(":")) return; // Kinder-, Schüler-, Lehrergeräte
    if (process.env.FUNCTIONS_EMULATOR === "true") return;
    const res = await fetch(RC_API + encodeURIComponent(user.uid), {
      method: "DELETE",
      headers: { Authorization: `Bearer ${process.env.REVENUECAT_SECRET_KEY}` },
      signal: AbortSignal.timeout(20000),
    });
    // 404: war nie Kunde
    if (!res.ok && res.status !== 404) console.error("RevenueCat löschen", res.status);
  });
