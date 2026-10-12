import { test } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import type { Request, Response } from "express";
import { clientIp, failedAuthGuard, limitKey, rateLimit } from "../src/util/rateLimit.js";
import { AppError } from "../src/util/errors.js";

const req = (ip: string, userId?: string) => ({ ip, user: userId ? { id: userId } : undefined }) as unknown as Request;
const run = (mw: (q: Request, r: Response, n: (e?: unknown) => void) => void, q: Request, res: Response = new EventEmitter() as unknown as Response) => {
  let err: unknown;
  mw(q, res, (e) => (err = e));
  return err;
};

test("limit key: authenticated requests use the user id, others the IP", () => {
  assert.equal(limitKey(req("1.2.3.4", "u1")), "u:u1");
  assert.equal(limitKey(req("1.2.3.4")), "ip:1.2.3.4");
  assert.equal(limitKey(req("1.2.3.4", "u1"), "ip"), "ip:1.2.3.4");
  assert.equal(clientIp({ socket: {} } as unknown as Request), "unknown");
});

test("rate limit: users behind one IP do not share a bucket", () => {
  const mw = rateLimit(2);
  assert.equal(run(mw, req("9.9.9.9", "a")), undefined);
  assert.equal(run(mw, req("9.9.9.9", "a")), undefined);
  assert.ok(run(mw, req("9.9.9.9", "a")) instanceof AppError);
  assert.equal(run(mw, req("9.9.9.9", "b")), undefined);
});

test("rate limit: unauthenticated routes are limited per IP", () => {
  const mw = rateLimit(1);
  assert.equal(run(mw, req("1.1.1.1")), undefined);
  assert.ok(run(mw, req("1.1.1.1")) instanceof AppError);
  assert.equal(run(mw, req("2.2.2.2")), undefined);
});

test("failed auth guard: an IP is refused after too many 401s, others are not", () => {
  const mw = failedAuthGuard(3, 60_000);
  const fail = (ip: string) => {
    const res = Object.assign(new EventEmitter(), { statusCode: 401 }) as unknown as Response;
    assert.equal(run(mw, req(ip), res), undefined);
    res.emit("finish");
  };
  fail("5.5.5.5");
  fail("5.5.5.5");
  fail("5.5.5.5");
  const blocked = run(mw, req("5.5.5.5"));
  assert.ok(blocked instanceof AppError && blocked.status === 429);
  assert.equal(run(mw, req("6.6.6.6")), undefined);
});

test("failed auth guard: successful requests are not counted", () => {
  const mw = failedAuthGuard(1, 60_000);
  for (let i = 0; i < 5; i++) {
    const res = Object.assign(new EventEmitter(), { statusCode: 200 }) as unknown as Response;
    assert.equal(run(mw, req("7.7.7.7"), res), undefined);
    res.emit("finish");
  }
});
