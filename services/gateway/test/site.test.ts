import assert from "node:assert/strict";
import { test } from "node:test";
import {
  NEVER_ANSWER,
  startFakeSite,
  type FakeSiteReply,
} from "../../../tests/integration/helpers.ts";
import { createSiteClient, SiteError, type UsageReport } from "../src/site.ts";

const SECRET = "s".repeat(48);
const TOKEN = "lba_" + "t".repeat(40);
const REPORT: UsageReport = {
  account_id: "6f1c0000-0000-4000-8000-000000000001",
  session_id: "sess-1",
  seq: 3,
  stt_ms_out: 10_000,
  stt_ms_in: 4_000,
  tts_chars: 120,
};

async function withSite(
  handle: (path: string, body: any) => FakeSiteReply | typeof NEVER_ANSWER,
  run: (
    site: Awaited<ReturnType<typeof startFakeSite>>,
    client: ReturnType<typeof createSiteClient>,
  ) => Promise<void>,
  timeoutMs?: number,
) {
  const site = await startFakeSite({ secret: SECRET, handle });
  const client = createSiteClient({
    socketPath: site.socketPath,
    host: site.host,
    secret: SECRET,
    timeoutMs,
  });
  try {
    await run(site, client);
  } finally {
    await site.close();
  }
}

const code = (expected: string) => (error: unknown) =>
  error instanceof SiteError && error.code === expected;

test("site: authorize maps a 200 to camelCase and signs the request", async () => {
  await withSite(
    () => ({
      status: 200,
      body: { account_id: "acc-1", balance_units: 42, has_purchase: true },
    }),
    async (site, client) => {
      assert.deepEqual(await client.authorize(TOKEN), {
        accountId: "acc-1",
        balanceUnits: 42,
        hasPurchase: true,
      });
      assert.deepEqual(site.failures, []);
      assert.equal(site.requests.length, 1);
      assert.equal(site.requests[0]!.path, "/internal/livebridge/v1/authorize/");
      assert.deepEqual(site.requests[0]!.body, { access_token: TOKEN });
    },
  );
});

test("site: a clock-skewed timestamp is refused by the site, so the client uses now()", async () => {
  const site = await startFakeSite({
    secret: SECRET,
    handle: () => ({ status: 200, body: { account_id: "a", balance_units: 1, has_purchase: false } }),
  });
  try {
    const stale = createSiteClient({
      socketPath: site.socketPath,
      host: site.host,
      secret: SECRET,
      now: () => Date.now() - 120_000,
    });
    await assert.rejects(stale.authorize(TOKEN), code("unavailable"));
    assert.equal(site.failures.length, 1);
    assert.match(site.failures[0]!, /timestamp stale/);
  } finally {
    await site.close();
  }
});

test("site: a wrong secret is a verification failure and maps to unavailable", async () => {
  const site = await startFakeSite({ secret: SECRET, handle: () => ({ status: 200, body: {} }) });
  try {
    const client = createSiteClient({
      socketPath: site.socketPath,
      host: site.host,
      secret: "x".repeat(48),
    });
    await assert.rejects(client.authorize(TOKEN), code("unavailable"));
    assert.match(site.failures[0]!, /signature/);
  } finally {
    await site.close();
  }
});

test("site: authorize 401 is invalid_token", async () => {
  await withSite(
    () => ({ status: 401, body: { error: "invalid_token" } }),
    async (_site, client) => {
      await assert.rejects(client.authorize(TOKEN), code("invalid_token"));
    },
  );
});

test("site: usage 200 maps to camelCase and sends the identical body each time", async () => {
  await withSite(
    () => ({ status: 200, body: { charged_units: 7, balance_units: 93 } }),
    async (site, client) => {
      const expected = { chargedUnits: 7, balanceUnits: 93 };
      assert.deepEqual(await client.usage(REPORT), expected);
      assert.deepEqual(await client.usage(REPORT), expected);
      assert.deepEqual(site.failures, []);
      assert.equal(site.requests[0]!.path, "/internal/livebridge/v1/usage/");
      assert.deepEqual(site.requests[0]!.body, REPORT);
      assert.equal(site.requests[0]!.rawBody, site.requests[1]!.rawBody);
    },
  );
});

test("site: usage 404 unknown_account, 400 bad_request", async () => {
  let reply: FakeSiteReply = { status: 404, body: { error: "unknown_account" } };
  await withSite(
    () => reply,
    async (_site, client) => {
      await assert.rejects(client.usage(REPORT), code("unknown_account"));
      reply = { status: 400, body: { error: "bad_request" } };
      await assert.rejects(client.usage(REPORT), code("bad_request"));
    },
  );
});

test("site: every other outcome is unavailable (HTML 404, 500, non-JSON or malformed 200)", async () => {
  const replies: FakeSiteReply[] = [
    { status: 404, body: "<html>Not Found</html>" },
    { status: 404, body: { error: "something_else" } },
    { status: 500, body: { error: "boom" } },
    { status: 200, body: "<html>ok</html>" },
    { status: 200, body: { account_id: "a", balance_units: "5", has_purchase: true } },
    { status: 200, body: { account_id: "a", balance_units: 5 } },
    { status: 200, body: { account_id: "a", balance_units: 1.5, has_purchase: true } },
    { status: 200, body: null },
  ];
  let next = 0;
  await withSite(
    () => replies[next]!,
    async (site, client) => {
      for (next = 0; next < replies.length; next++) {
        await assert.rejects(client.authorize(TOKEN), code("unavailable"), `reply ${next}`);
      }
      // Unavailable for the reply's own sake, not because the site refused the signature.
      assert.deepEqual(site.failures, []);
      assert.equal(site.requests.length, replies.length);
    },
  );
  await withSite(
    () => ({ status: 200, body: { charged_units: 1 } }),
    async (site, client) => {
      await assert.rejects(client.usage(REPORT), code("unavailable"));
      assert.deepEqual(site.failures, []);
      assert.equal(site.requests.length, 1);
    },
  );
});

test("site: a server that never answers is unavailable after timeoutMs", async () => {
  await withSite(
    () => NEVER_ANSWER,
    async (_site, client) => {
      const started = Date.now();
      await assert.rejects(client.authorize(TOKEN), code("unavailable"));
      const took = Date.now() - started;
      assert.ok(took >= 150 && took < 2000, `took ${took} ms`);
    },
    200,
  );
});

test("site: a missing socket file is unavailable", async () => {
  const client = createSiteClient({
    socketPath: "/nonexistent/lb-site.sock",
    host: "jaysonkhan.com",
    secret: SECRET,
  });
  await assert.rejects(client.authorize(TOKEN), code("unavailable"));
});

test("site: errors never carry the token, the secret or a response body", async () => {
  await withSite(
    () => ({ status: 500, body: `leak ${TOKEN} ${SECRET}` }),
    async (site, client) => {
      await assert.rejects(client.authorize(TOKEN), (error: unknown) => {
        const text = String((error as Error).message) + String((error as Error).stack);
        assert.ok(!text.includes(TOKEN) && !text.includes(SECRET) && !text.includes("leak"));
        return error instanceof SiteError;
      });
      assert.deepEqual(site.failures, []);
      assert.equal(site.requests.length, 1);
    },
  );
});

test("site: every call opens its own connection (none is pooled for reuse)", async () => {
  await withSite(
    () => ({ status: 200, body: { charged_units: 1, balance_units: 1 } }),
    async (site, client) => {
      await client.usage(REPORT);
      await client.usage(REPORT);
      assert.equal(site.requests.length, 2);
      // Without `agent: false` the global agent sends keep-alive and may reuse the socket.
      for (const request of site.requests) assert.equal(request.headers.connection, "close");
    },
  );
});
