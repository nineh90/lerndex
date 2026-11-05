// RevenueCat-Kunde → Abo-Status von Lerndex. Ohne Firebase, einzeln testbar.

const ENTITLEMENT = "premium";
const EXTRA_SLOT_PRODUCT = "lerndex_extra_child_slot";

/**
 * Plan aus der Produkt-ID (wie SubscriptionPlanExtension.fromEntitlement in
 * der App). Unbekannte Produkte mit aktivem Entitlement zählen als solo:
 * Wer zahlt, darf nie ohne Zugang dastehen.
 */
function planFromProduct(productId) {
  const id = String(productId || "").toLowerCase();
  if (id.includes("family")) return "family";
  if (id.includes("duo")) return "duo";
  return "solo";
}

function parseDate(value) {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** subscriber aus GET /v1/subscribers/{id} → { plan, isActive, isTrial, expiresAt, extraChildSlots } */
function statusFromSubscriber(subscriber, now = new Date()) {
  const entitlement = subscriber?.entitlements?.[ENTITLEMENT];
  const extraChildSlots = (subscriber?.non_subscriptions?.[EXTRA_SLOT_PRODUCT] || []).length;
  if (!entitlement) {
    return { plan: "none", isActive: false, isTrial: false, expiresAt: null, extraChildSlots };
  }
  const expiresAt = parseDate(entitlement.expires_date);
  const isActive = expiresAt == null || expiresAt > now;
  const product = entitlement.product_identifier;
  const sub = subscriber?.subscriptions?.[product];
  return {
    plan: isActive ? planFromProduct(product) : "none",
    isActive,
    isTrial: isActive && sub?.period_type === "trial",
    expiresAt,
    extraChildSlots,
  };
}

module.exports = { statusFromSubscriber, planFromProduct, EXTRA_SLOT_PRODUCT };
