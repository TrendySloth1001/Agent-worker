import { test } from "node:test";
import assert from "node:assert/strict";
import { isPrivateIp } from "../src/ingest/fetcher.js";

test("ip guard: plain private, loopback and public addresses", () => {
  for (const ip of ["10.0.0.1", "127.0.0.1", "192.168.1.5", "169.254.169.254", "::1", "fd00::1", "fe80::1"]) assert.equal(isPrivateIp(ip), true, ip);
  for (const ip of ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111"]) assert.equal(isPrivateIp(ip), false, ip);
});

test("ip guard: IPv4-mapped IPv6", () => {
  assert.equal(isPrivateIp("::ffff:10.0.0.1"), true);
  assert.equal(isPrivateIp("::ffff:7f00:1"), true);
  assert.equal(isPrivateIp("::ffff:8.8.8.8"), false);
});

test("ip guard: NAT64 (64:ff9b::/96) embedding a private IPv4 is blocked", () => {
  assert.equal(isPrivateIp("64:ff9b::7f00:1"), true); // 127.0.0.1
  assert.equal(isPrivateIp("64:ff9b::a9fe:a9fe"), true); // 169.254.169.254
  assert.equal(isPrivateIp("64:ff9b::10.0.0.5"), true);
  assert.equal(isPrivateIp("64:ff9b::808:808"), false); // 8.8.8.8
});

test("ip guard: 6to4 (2002::/16) embedding a private IPv4 is blocked", () => {
  assert.equal(isPrivateIp("2002:7f00:1::1"), true); // 127.0.0.1
  assert.equal(isPrivateIp("2002:c0a8:101::"), true); // 192.168.1.1
  assert.equal(isPrivateIp("2002:a9fe:a9fe::1"), true); // 169.254.169.254
  assert.equal(isPrivateIp("2002:808:808::1"), false); // 8.8.8.8
});

test("ip guard: IPv4-compatible ::a.b.c.d with a private address is blocked", () => {
  assert.equal(isPrivateIp("::127.0.0.1"), true);
});
