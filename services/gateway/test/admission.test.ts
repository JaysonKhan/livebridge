import assert from "node:assert/strict";
import { test } from "node:test";
import { Admission } from "../src/admission.ts";
import type { Ticket } from "../src/admission.ts";

const caps = { total: 6, account: 4, keys: 2, paidReserved: 1 };
const token = { mode: "token" } as const;
const keys = { mode: "keys" } as const;
const trial = (id: string) => ({ mode: "account", accountId: id, hasPurchase: false }) as const;
const paid = (id: string) => ({ mode: "account", accountId: id, hasPurchase: true }) as const;

function ticketOf(r: { ok: boolean; ticket?: Ticket }): Ticket {
  assert.ok(r.ok && r.ticket, "expected admission");
  return r.ticket;
}

test("admission: total cap counts every mode", () => {
  const a = new Admission({ total: 3, account: 3, keys: 3, paidReserved: 0 });
  assert.ok(a.admit(token).ok);
  assert.ok(a.admit(keys).ok);
  assert.ok(a.admit(paid("a1")).ok);
  for (const who of [token, keys, paid("a2")]) assert.equal(a.admit(who).ok, false);
});

test("admission: account and keys caps are separate; tokens only hit the total", () => {
  const a = new Admission({ total: 10, account: 2, keys: 1, paidReserved: 0 });
  assert.ok(a.admit(keys).ok);
  assert.equal(a.admit(keys).ok, false);
  assert.ok(a.admit(paid("a1")).ok);
  assert.ok(a.admit(paid("a2")).ok);
  assert.equal(a.admit(paid("a3")).ok, false);
  // Full keys and account caps do not block token sessions.
  assert.ok(a.admit(token).ok);
});

test("admission: reserved slots are held back from trial-only accounts (account cap)", () => {
  const a = new Admission(caps);
  for (const id of ["a1", "a2", "a3"]) assert.ok(a.admit(paid(id)).ok);
  assert.equal(a.admit(trial("t1")).ok, false);
  assert.ok(a.admit(paid("p4")).ok);
  assert.equal(a.admit(paid("p5")).ok, false);
});

test("admission: reserved slots are held back from trial-only accounts (total cap)", () => {
  const a = new Admission(caps);
  // 2 keys + 3 tokens = 5 of 6 total; account count stays 0.
  for (const who of [keys, keys, token, token, token]) assert.ok(a.admit(who).ok);
  assert.equal(a.admit(trial("t1")).ok, false);
  assert.ok(a.admit(paid("p1")).ok);
  assert.equal(a.admit(token).ok, false);
});

test("admission: reservation does not apply to token and keys sessions", () => {
  const a = new Admission(caps);
  for (const who of [token, token, token, token, keys]) assert.ok(a.admit(who).ok);
  assert.ok(a.admit(keys).ok); // the 6th, in the reserved slot
  assert.equal(a.admit(token).ok, false);
});

test("admission: a second admit for an account replaces the first, even when full", () => {
  const a = new Admission({ total: 1, account: 1, keys: 1, paidReserved: 0 });
  const first = ticketOf(a.admit(paid("a1")));
  assert.equal(a.admit(token).ok, false);
  const r = a.admit(paid("a1"));
  assert.ok(r.ok);
  assert.equal(r.replaces, first);
  assert.notEqual(r.ticket, first);
  // Counts unchanged: still full.
  assert.equal(a.admit(token).ok, false);
});

test("admission: replace also works for a trial account at its reduced cap", () => {
  const a = new Admission(caps);
  // Trial cap is account - paidReserved = 3; fill it with trial accounts.
  for (const id of ["t1", "t2", "t3"]) assert.ok(a.admit(trial(id)).ok);
  assert.equal(a.admit(trial("t4")).ok, false);
  const r = a.admit(trial("t1"));
  assert.ok(r.ok && r.replaces);
});

test("admission: releasing the replaced ticket is a no-op; releasing the new one frees the slot", () => {
  const a = new Admission({ total: 1, account: 1, keys: 1, paidReserved: 0 });
  const old = ticketOf(a.admit(paid("a1")));
  const r = a.admit(paid("a1"));
  const fresh = ticketOf(r);
  a.release(old);
  assert.equal(a.admit(token).ok, false, "old release must not free the slot");
  assert.equal(a.admit(paid("b")).ok, false, "nor the account slot");
  a.release(fresh);
  assert.ok(a.admit(token).ok, "new release frees it");
});

test("admission: release frees a slot exactly once", () => {
  const a = new Admission({ total: 2, account: 2, keys: 2, paidReserved: 0 });
  const t1 = ticketOf(a.admit(token));
  ticketOf(a.admit(token));
  a.release(t1);
  a.release(t1);
  assert.ok(a.admit(token).ok);
  assert.equal(a.admit(token).ok, false, "double release must not open a second slot");
});

test("admission: releasing an account ticket lets the account in again without replacement", () => {
  const a = new Admission(caps);
  const t = ticketOf(a.admit(paid("a1")));
  a.release(t);
  const r = a.admit(paid("a1"));
  assert.ok(r.ok);
  assert.equal(r.replaces, undefined);
});

test("admission: tickets expose mode and accountId read-only", () => {
  const a = new Admission(caps);
  const t = ticketOf(a.admit(paid("a1")));
  assert.equal(t.mode, "account");
  assert.equal(t.accountId, "a1");
  assert.equal(ticketOf(a.admit(token)).mode, "token");
});

test("admission: releasing frees the per-mode slot, not just the total", () => {
  const k = new Admission({ total: 10, account: 10, keys: 1, paidReserved: 0 });
  const kt = ticketOf(k.admit(keys));
  assert.equal(k.admit(keys).ok, false);
  k.release(kt);
  assert.ok(k.admit(keys).ok, "keys slot reopens");

  const a = new Admission({ total: 10, account: 1, keys: 10, paidReserved: 0 });
  const at = ticketOf(a.admit(paid("a1")));
  assert.equal(a.admit(paid("a2")).ok, false);
  a.release(at);
  assert.ok(a.admit(paid("a2")).ok, "account slot reopens");
});
