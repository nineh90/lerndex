// Zugang eines Elternkontos (Abo, Schullizenz, Testzugang) – ohne Firebase,
// einzeln testbar. Gleiche Logik wie SubscriptionStatus in der App.

// Wie lange ein abgelaufenes Abo noch gilt (Verlängerung kommt per Webhook
// manchmal mit Verzögerung an)
const GRACE_MS = 3 * 24 * 60 * 60 * 1000;

/** Hat das Elternkonto ein aktives Abo, eine Schullizenz oder Testzugang? */
function hasAccess(data, now = Date.now()) {
  if (!data) return false;
  if (data.testAccess === true) return true;
  const license = data.schoolLicenseUntil?.toMillis?.() ?? 0;
  if (license > now) return true;
  const sub = data.subscription;
  if (!sub || sub.isActive !== true) return false;
  const expires = sub.expiresAt?.toMillis?.();
  return expires == null || expires + GRACE_MS > now;
}

module.exports = { hasAccess, GRACE_MS };
