const test = require("node:test");
const assert = require("node:assert/strict");
const h = require("../lib/helpers");

// Erwartete Werte von ParentPin (lib/src/features/parent_dashboard/domain/
// parent_pin_model.dart) berechnet – bestehende PINs müssen nach dem Umzug
// auf den Server weiter funktionieren.
test("PIN-Hash wie in der App", () => {
  assert.equal(
    h.hashPin("1234", "c2FsdC1zYWx0LXNhbHQ="),
    "KEmluE395OwJgkUxXrBCI3ib8JPx-K_m-lKnO23GIB8=",
  );
  assert.equal(
    h.hashPin("987654", "AbC-_dEf12345678ghIJkg=="),
    "XwkgJ-zXjP0W2nph8D8vmVyty7_d13WhFb03YjPT9j4=",
  );
});

test("alter PIN-Hash wie in der App", () => {
  assert.equal(h.legacyHashPin("1234"), "1509442");
  assert.equal(h.legacyHashPin("0000"), "1477632");
  assert.equal(h.legacyHashPin("999999"), "1686256992");
});

test("Kopplungscodes", () => {
  const code = h.newPairingCode();
  assert.match(code, /^[A-HJ-NP-Z2-9]{8}$/);
  assert.equal(h.normalizeCode(" k7mx-q2pa "), "K7MXQ2PA");
  assert.equal(h.normalizeCode("K7MXQ2P"), null); // zu kurz
  assert.equal(h.normalizeCode("K7MXQ2P0"), null); // 0 gibt es nicht
  assert.equal(h.normalizeCode(42), null);
});

test("Kind-UID wie in account.dart", () => {
  assert.equal(h.kidUid("p1", "c1"), "kid:p1:c1");
});
