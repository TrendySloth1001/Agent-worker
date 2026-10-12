import { test } from "node:test";
import assert from "node:assert/strict";
import { detectPii, hasPii, hasSecret, ibanValid, isAadhaar, luhn, redact, redactForExternal, safetyNote, sanitizeMemory, verhoeff } from "../src/nlp/pii.js";
import { looksSensitive, planOps } from "../src/memory/logic.js";

const kinds = (t: string) => detectPii(t).map((s) => s.kind);

test("checksums", () => {
  assert.ok(luhn("4111111111111111"));
  assert.ok(!luhn("4111111111111112"));
  assert.ok(verhoeff("234567890124"));
  assert.ok(!verhoeff("234567890123"));
  assert.ok(isAadhaar("234567890124"));
  assert.ok(!isAadhaar("134567890124")); // cannot start with 0/1 (and fails the checksum)
  assert.ok(ibanValid("GB82 WEST 1234 5698 7654 32"));
  assert.ok(!ibanValid("GB82 WEST 1234 5698 7654 33"));
});

test("emails", () => {
  assert.deepEqual(kinds("mail me at jane.doe+x@example.co.in please"), ["email"]);
  assert.equal(redact("mail jane@example.com now"), "mail [EMAIL] now");
  assert.deepEqual(kinds("use user@localhost or @handle or a@b"), []);
});

test("phone numbers (Indian and international)", () => {
  for (const t of ["call +91 98765 43210", "call 9876543210", "call +91-9876543210", "call 09876543210", "call +44 20 7946 0958", "call +1 (415) 555-2671", "call (415) 555-2671", "call 415-555-2671"]) {
    assert.deepEqual(kinds(t), ["phone"], t);
  }
  assert.equal(redact("ring +91 98765 43210 today"), "ring [PHONE] today");
});

test("credit cards need a valid Luhn checksum and issuer", () => {
  for (const c of ["4111111111111111", "4111 1111 1111 1111", "4111-1111-1111-1111", "5500005555555559", "378282246310005", "3782 822463 10005", "6011111111111117"]) {
    assert.deepEqual(kinds(`card ${c} ok`), ["card"], c);
  }
  assert.deepEqual(kinds("card 4111111111111112"), []);
  assert.deepEqual(kinds("card 4111 1111 1111 1112"), []);
  assert.equal(redact("pay 4111 1111 1111 1111 now"), "pay [CARD] now");
});

test("Aadhaar needs a valid Verhoeff checksum", () => {
  assert.deepEqual(kinds("aadhaar 234567890124"), ["aadhaar"]);
  assert.deepEqual(kinds("aadhaar 2345 6789 0124"), ["aadhaar"]);
  assert.deepEqual(kinds("aadhaar 2345-6789-0124"), ["aadhaar"]);
  assert.deepEqual(kinds("aadhaar 234567890123"), []);
  assert.deepEqual(kinds("aadhaar 2345 6789 0123"), []);
});

test("PAN", () => {
  assert.deepEqual(kinds("PAN is ABCPE1234F"), ["pan"]);
  assert.deepEqual(kinds("PAN is ABCZE1234F"), []); // 4th letter is not a holder type
  assert.deepEqual(kinds("PAN is abcpe1234f"), []);
  assert.deepEqual(kinds("constant ABCDE12345"), []);
});

test("IBAN needs mod-97", () => {
  assert.deepEqual(kinds("iban GB82WEST12345698765432"), ["iban"]);
  assert.deepEqual(kinds("iban GB82 WEST 1234 5698 7654 32"), ["iban"]);
  assert.deepEqual(kinds("iban DE89 3704 0044 0532 0130 00"), ["iban"]);
  assert.deepEqual(kinds("iban GB82WEST12345698765433"), []);
});

test("API keys and tokens", () => {
  for (const k of [
    "sk-proj-abcdefghijklmnopqrstuvwxyz123456",
    "sk-ant-api03-abcdefghijklmnopqrstuvwx",
    "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
    "AKIAIOSFODNN7EXAMPLE",
    "xoxb-1234567890-abcdefghij",
    "AIzaSyA1234567890abcdefghijklmnopqrstuv",
    "sk_live_abcdefghijklmnop1234",
  ]) {
    assert.deepEqual(kinds(`key ${k} here`), ["api_key"], k);
  }
  assert.deepEqual(kinds("api_key = Zx81kLmN02pQrStUvW"), ["api_key"]);
  assert.deepEqual(kinds("Authorization: Bearer abcdEFGH1234ijklMNOP5678qrst"), ["api_key"]);
  // words that merely describe a key are not keys
  assert.deepEqual(kinds("the api key is required for auth"), []);
  assert.deepEqual(kinds("token: description"), []);
});

test("JWTs, private keys and passwords", () => {
  const jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U";
  assert.deepEqual(kinds(`token ${jwt}`), ["jwt"]);
  const pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKj34GkxFhD90vcNLYLInFEX6Ppy1tPf9Cnzj4p4WGeKLs1Pt8Qu\n-----END RSA PRIVATE KEY-----";
  assert.deepEqual(kinds(`here\n${pem}\nthanks`), ["private_key"]);
  assert.equal(redact(`k:\n${pem}\nend`), "k:\n[PRIVATE_KEY]\nend");
  assert.deepEqual(kinds("-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASC"), ["private_key"]); // truncated paste
  assert.equal(redact("my password: hunter2 ok"), "my password: [PASSWORD] ok");
  assert.equal(redact("password is s3cr3t!"), "password is [PASSWORD]");
  assert.deepEqual(kinds("how do I reset my password?"), []);
});

test("IP addresses", () => {
  assert.deepEqual(kinds("server at 192.168.1.20 and 8.8.8.8"), ["ip", "ip"]);
  assert.deepEqual(kinds("ipv6 2001:0db8:85a3:0000:0000:8a2e:0370:7334"), ["ip"]);
  assert.deepEqual(kinds("ipv6 fe80::1ff:fe23:4567:890a"), ["ip"]);
  assert.equal(redact("ping 10.0.0.5 now"), "ping [IP] now");
  // not addresses
  assert.deepEqual(kinds("localhost 127.0.0.1 and 0.0.0.0"), []);
  assert.deepEqual(kinds("version 1.2.3 and v10.0.1.2"), []);
  assert.deepEqual(kinds("999.1.1.1 and 1.2.3"), []);
  assert.deepEqual(kinds("std::vector<int> a::b"), []);
});

test("no false positives on versions, timestamps, UUIDs, hashes and code", () => {
  const benign = [
    "node 22.11.0 and react 18.3.1",
    "released 2026-10-12T14:30:00.000Z",
    "at 10:30:00 +05:30 local time",
    "ts=1728743400000 ts2=1728743400",
    "id 550e8400-e29b-41d4-a716-446655440000",
    "id 12345678-1234-1234-1234-123456789012",
    "sha 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
    "build 20261012140000",
    "order #1234567890123456",
    "pi is 3.14159265358979",
    "the year 2026 and 1,234,567 rows",
    "const x = a.b.c.d.e;",
    "sku ABCDE12345 / ISO 8601 / RFC 2616",
  ];
  for (const t of benign) assert.deepEqual(kinds(t), [], t);
});

test("redact keeps order and handles several spans", () => {
  const t = "mail a@b.com or +91 98765 43210; card 4111 1111 1111 1111; ip 8.8.4.4";
  assert.equal(redact(t), "mail [EMAIL] or [PHONE]; card [CARD]; ip [IP]");
  assert.equal(redact("nothing here"), "nothing here");
  assert.equal(redact("a@b.com", ["phone"]), "a@b.com"); // only requested kinds
  const spans = detectPii("x a@b.com y");
  assert.deepEqual(spans.map((s) => [s.kind, s.start, s.end, s.value]), [["email", 2, 9, "a@b.com"]]);
});

test("an email is not also reported as a phone or key", () => {
  assert.deepEqual(kinds("919876543210@example.com"), ["email"]);
});

test("hasPii and hasSecret", () => {
  assert.ok(hasPii("a@b.com"));
  assert.ok(!hasSecret("a@b.com"));
  assert.ok(hasSecret("card 4111 1111 1111 1111"));
  assert.ok(hasSecret("aadhaar 234567890124"));
});

test("memory policy", () => {
  assert.equal(sanitizeMemory("User's card is 4111 1111 1111 1111"), null);
  assert.equal(sanitizeMemory("password: hunter2", true), null); // secrets are dropped even when explicit
  assert.equal(sanitizeMemory("Reach the user at jane@example.com"), "Reach the user at [EMAIL]");
  assert.equal(sanitizeMemory("Reach the user at jane@example.com", true), "Reach the user at jane@example.com");
  assert.equal(sanitizeMemory("User prefers TypeScript"), "User prefers TypeScript");
  assert.ok(looksSensitive("my aadhaar is 2345 6789 0124"));
  assert.ok(!looksSensitive("order 1728743400000 shipped"));
});

test("planOps redacts contacts unless the user said remember", () => {
  const ops = [{ op: "ADD" as const, text: "User's phone is +91 98765 43210", kind: "fact" as const }];
  const auto = planOps(ops, [], { explicit: null, total: 0 });
  assert.equal((auto[0] as { text: string }).text, "User's phone is [PHONE]");
  const explicit = planOps(ops, [], { explicit: { type: "remember", subject: "x" }, total: 0 });
  assert.equal((explicit[0] as { text: string }).text, "User's phone is +91 98765 43210");
  assert.deepEqual(planOps([{ op: "ADD", text: "User's Aadhaar is 2345 6789 0124", kind: "fact" }], [], { explicit: { type: "remember", subject: "x" }, total: 0 }), []);
});

test("external redaction and safety note", () => {
  assert.equal(redactForExternal("who is jane@example.com  at 10.1.2.3"), "who is [EMAIL] at [IP]");
  assert.equal(safetyNote("how do I install node"), null);
  assert.equal(safetyNote("my email is a@b.com"), null);
  const note = safetyNote("my card is 4111 1111 1111 1111 and password: hunter2")!;
  assert.match(note, /payment card/);
  assert.match(note, /password/);
  assert.ok(!note.includes("4111") && !note.includes("hunter2"));
});
