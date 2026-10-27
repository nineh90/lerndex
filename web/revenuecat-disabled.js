// Leeres Modul statt RevenueCat Web Billing (siehe Import-Map in index.html).
// Das Plugin lädt sein Skript sonst schon beim Start von cdn.jsdelivr.net,
// und das zieht Stripe.js samt Telemetrie nach – auch ohne Kauf.
export {};
