// Session admission: per-mode caps, slots held back for paying accounts, and
// one live session per account. Pure bookkeeping (integers and a Map) so it is
// free to call once per session; no timers, no I/O, no logging.

export interface AdmissionCaps {
  total: number; // every mode together
  account: number; // account sessions
  keys: number; // own-keys sessions
  paidReserved: number; // slots held back for accounts that have a purchase
}

export type Who =
  | { mode: "token" }
  | { mode: "keys" }
  | { mode: "account"; accountId: string; hasPurchase: boolean };

// Opaque handle: identity is what matters. Pass it back to release().
export interface Ticket {
  readonly mode: Who["mode"];
  readonly accountId?: string;
}

export type AdmitResult =
  | { ok: true; ticket: Ticket; replaces?: Ticket }
  | { ok: false };

export class Admission {
  private totalUsed = 0;
  private accountUsed = 0;
  private keysUsed = 0;
  // Tickets that currently hold a slot. A replaced or released ticket is gone
  // from here, which is what makes a late release() of it a no-op.
  private readonly live = new Set<Ticket>();
  private readonly byAccount = new Map<string, Ticket>();

  private readonly caps: AdmissionCaps;

  constructor(caps: AdmissionCaps) {
    this.caps = caps;
  }

  admit(who: Who): AdmitResult {
    if (who.mode === "account") {
      const old = this.byAccount.get(who.accountId);
      if (old) {
        // The new session takes over the old one's slot: counts stay put, so
        // this succeeds even when every cap is full.
        const ticket: Ticket = { mode: "account", accountId: who.accountId };
        this.live.delete(old);
        this.live.add(ticket);
        this.byAccount.set(who.accountId, ticket);
        return { ok: true, ticket, replaces: old };
      }
      const hold = who.hasPurchase ? 0 : this.caps.paidReserved;
      if (
        this.accountUsed >= this.caps.account - hold ||
        this.totalUsed >= this.caps.total - hold
      ) {
        return { ok: false };
      }
      const ticket: Ticket = { mode: "account", accountId: who.accountId };
      this.accountUsed++;
      this.totalUsed++;
      this.live.add(ticket);
      this.byAccount.set(who.accountId, ticket);
      return { ok: true, ticket };
    }
    if (this.totalUsed >= this.caps.total) return { ok: false };
    if (who.mode === "keys") {
      if (this.keysUsed >= this.caps.keys) return { ok: false };
      this.keysUsed++;
    }
    this.totalUsed++;
    const ticket: Ticket = { mode: who.mode };
    this.live.add(ticket);
    return { ok: true, ticket };
  }

  release(ticket: Ticket): void {
    if (!this.live.delete(ticket)) return;
    this.totalUsed--;
    if (ticket.mode === "account") {
      this.accountUsed--;
      if (ticket.accountId !== undefined) this.byAccount.delete(ticket.accountId);
    } else if (ticket.mode === "keys") {
      this.keysUsed--;
    }
  }
}
