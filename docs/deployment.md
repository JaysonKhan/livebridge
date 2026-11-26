# Gateway deployment

**First deployed on 2026-11-26**, with the owner's go-ahead: Node.js on the server, the repository under
`/var/www/livebridge`, the systemd service, and a hostname of its own with a Let's Encrypt certificate and the
sample nginx vhost — the gateway answers over HTTPS and `./deploy.sh` has run end to end. The steps assume a
conventional Linux server: plain systemd services under
`/var/www/<name>`, an nginx reverse proxy, Let's Encrypt certificates, and a `./deploy.sh` that never edits files on
the server. Server-specific details (addresses, other services, security tooling) are deliberately not recorded in
this repository.

## What runs where

- The gateway is one Node.js process listening on `127.0.0.1:8201` (pick another port with `PORT` if it is taken).
  No database, no disk writes; sessions live in memory.
- nginx terminates TLS and proxies `/v1/*` (including the WebSocket upgrade) and `/healthz`.
- Provider keys live only in `/var/www/livebridge/.env` on the server.

## Decisions to make first

1. **Hostname.** A dedicated subdomain (e.g. `bridge.example.com`) with its own DNS A record and certificate.
2. **Node.js on the server.** The gateway needs Node ≥ 22.18 (it runs the TypeScript sources directly). Check with
   `ssh <server> "node -v"`; installing Node 24 LTS is a server change to approve first. On Ubuntu the NodeSource
   apt repository gives `/usr/bin/node`, the path the systemd unit expects: add its signing key to
   `/etc/apt/keyrings`, a `node_24.x` line to `/etc/apt/sources.list.d/`, then `apt-get install nodejs`. That
   repository is outside the system's automatic security updates, so Node is updated by hand.
3. **Region.** The gateway sits between the Mac and the providers, so its location matters. Run `npm run bench` from
   the Mac and from the server before deciding — do not move anything on a guess. `ELEVENLABS_BASE_URL` can point at
   a regional host.
4. **Keys.** Use dedicated, limited provider keys (speech-only for ElevenLabs, with a monthly cap) rather than keys
   shared with another production service, so a long call cannot exhaust that service's credit.

## First-time setup (once, after approval)

```bash
# 1. Server directory and environment file
ssh <server> "sudo mkdir -p /var/www/livebridge && sudo chown deploy:deploy /var/www/livebridge && git clone <repo> /var/www/livebridge"
scp .env <server>:/var/www/livebridge/.env && ssh <server> "chmod 600 /var/www/livebridge/.env"
ssh <server> "cd /var/www/livebridge && npm ci --omit=dev"

# 2. Service
ssh <server> "sudo cp /var/www/livebridge/infra/livebridge-gateway.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now livebridge-gateway"
ssh <server> "curl -s http://127.0.0.1:8201/healthz"      # {"ok":true}

# 3. TLS + nginx (after the DNS record resolves)
ssh <server> "sudo certbot certonly --nginx -d bridge.example.com"
#    copy infra/nginx-livebridge.conf.sample to /etc/nginx/sites-enabled/livebridge.conf with the real hostname
ssh <server> "sudo nginx -t && sudo systemctl reload nginx"
curl -s https://bridge.example.com/healthz
```

In the app, set **Gateway URL** to `https://bridge.example.com` and paste the `GATEWAY_ACCESS_TOKEN` value.

## Every later deploy

```bash
export LIVEBRIDGE_SSH_HOST=<server>
./deploy.sh            # typecheck + tests, push, server reset to origin/main, npm ci, restart, health check
./deploy.sh --status
./deploy.sh --logs
```

## Accounts and own keys

The gateway starts a session in one of three ways (`POST /v1/sessions`):

- **Token** — the static `GATEWAY_ACCESS_TOKEN`, as before. An empty `GATEWAY_ACCESS_TOKEN` switches this mode off
  (`401 unauthorized`); accounts and own keys keep working.
- **Account** — the app's access token from the owner's site (`Bearer lba_…`). The gateway asks the site once, when the
  session starts, who the account is and whether its balance is above zero, then reports usage in the background every
  `USAGE_REPORT_SECONDS`. The gateway sends raw counters only (audio milliseconds per direction, synthesis characters);
  the site turns them into a charge.
- **Own keys** — the caller's own ElevenLabs and Gemini keys in the request body. Nothing is billed by the service.
  **Off unless** `MAX_KEYS_SESSIONS` is set above 0: until then an own-keys request gets `429 session_limit` and
  `GET /v1/voices` with a key gets `401 unauthorized`, so a stranger cannot hold a self-hosted gateway's slots.

Accounts are **off unless both** `SITE_SOCKET_PATH` and `LIVEBRIDGE_GATEWAY_SECRET` are set; until then an account
request gets `503 accounts_unavailable`. The `gateway.listening` log line says `accounts: true` once they are on.

### New `.env` keys

| Key | Default | Meaning |
|---|---|---|
| `SITE_SOCKET_PATH` | empty | The site's Gunicorn unix socket; its path is in your server notes. Empty = accounts off. |
| `SITE_HOST` | `jaysonkhan.com` | Host header sent on that socket; must be a host the site accepts. |
| `LIVEBRIDGE_GATEWAY_SECRET` | empty | Shared secret that signs every call to the site: at least 32 characters, the same value as in the site's `.env`. Empty = accounts off. |
| `ACCOUNT_VOICE_IDS` | empty | Comma-separated voice ids an account session may choose. The two configured voices are always allowed; while the list is empty, the provider's stock voices are allowed too. `GET /v1/voices` shows an account exactly these. |
| `MAX_ACCOUNT_SESSIONS` | `MAX_SESSIONS` | Cap on account sessions. |
| `MAX_KEYS_SESSIONS` | `0` (off) | Cap on own-keys sessions. Empty or 0 = own keys off. The hosted gateway sets it explicitly. |
| `PAID_RESERVED_SESSIONS` | `0` | Slots held back for accounts that have made a purchase: an account with only the trial gets `429 session_limit` once no more than this many slots are left (of `MAX_SESSIONS` or of `MAX_ACCOUNT_SESSIONS`). Token and own-keys sessions are bounded by their caps only. |
| `IDLE_TIMEOUT_MINUTES` | `10` | No recognised speech in either direction for this long ends the session (`idle_timeout`). 0 = off. |
| `USAGE_REPORT_SECONDS` | `10` | How often an account session reports usage to the site (2 to 60; the interval bounds how far an empty account can overrun). |

`MAX_SESSIONS` stays the cap on all sessions together, own-keys sessions included.

### Sizing `MAX_SESSIONS`

A voiced session holds two realtime speech-to-text connections (one per direction) and two speech synthesis
connections. The ElevenLabs plan limits each kind on its own, so size by whichever is tighter, and check both limits
for the plan in use:

```
MAX_SESSIONS = min(realtime speech-to-text concurrency / 2, speech synthesis concurrency / 2) − 1      rounded down
```

The 1 is a margin for a reconnect or a benchmark run. A plan that allows 10 concurrent realtime transcriptions and 10
concurrent syntheses gives `MAX_SESSIONS=4`. Keep `MAX_ACCOUNT_SESSIONS` and `MAX_KEYS_SESSIONS` at or below it.

### Adding them on the server

The server's `.env` is edited by hand, on the server: it is not in git and `deploy.sh` never touches it.

1. Add the new lines to `/var/www/livebridge/.env` (the socket path is in your server notes; leave
   `MAX_ACCOUNT_SESSIONS` empty to use `MAX_SESSIONS`; own keys stay off until `MAX_KEYS_SESSIONS` is set, so set it
   explicitly):

   ```
   SITE_SOCKET_PATH=<the site's Gunicorn socket>
   SITE_HOST=jaysonkhan.com
   ACCOUNT_VOICE_IDS=
   MAX_SESSIONS=<from the plan, see above>
   MAX_ACCOUNT_SESSIONS=
   MAX_KEYS_SESSIONS=<how many own-keys sessions to allow; 0 = off>
   PAID_RESERVED_SESSIONS=0
   IDLE_TIMEOUT_MINUTES=10
   USAGE_REPORT_SECONDS=10
   ```

2. Copy the shared secret from the site's `.env` without printing it. The first command removes an old line; the
   second appends the site's line after an empty one, so it cannot join a last line that has no newline (an empty
   line is harmless); the last prints only a count, which must be `1`:

   ```bash
   ssh <server>
   cd /var/www/livebridge
   sed -i '/^LIVEBRIDGE_GATEWAY_SECRET=/d' .env
   { echo; grep -m1 '^LIVEBRIDGE_GATEWAY_SECRET=' <site directory>/.env; } >> .env
   grep -c '^LIVEBRIDGE_GATEWAY_SECRET=.\{32,\}' .env
   ```

   If the site has no secret yet, generate one (`openssl rand -base64 36`), put the same value in both files and
   restart the site.

3. Deploy, and reinstall the unit whenever `infra/livebridge-gateway.service` changed. The accounts step changed it:
   `AF_UNIX` lets the gateway reach the site's socket (without it every site call fails), and the stop timeout leaves
   room for the final usage reports.

   ```bash
   LIVEBRIDGE_SSH_HOST=<server> ./deploy.sh
   ssh <server> "sudo cp /var/www/livebridge/infra/livebridge-gateway.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl restart livebridge-gateway"
   LIVEBRIDGE_SSH_HOST=<server> ./deploy.sh --logs     # gateway.listening … "accounts":true
   ```

The socket must not live under `/tmp` or `/home` (the unit's `PrivateTmp` and `ProtectHome` hide both from the
gateway). The gateway's user needs search (`x`) permission on every directory above the socket and write permission
on the socket itself.

### Log events worth watching

| Event | What it means |
|---|---|
| `site.authorize_failed` (`code`) | The site could not authorize an account; the app was told `503 billing_unavailable`. If every account start fails, check the socket path and its permissions, `AF_UNIX` in the installed unit, the secret, and that the site is up. |
| `billing.report_failed` (`seq`, `failures`, `code`) | A usage report was not accepted. The identical report goes again at the next interval. |
| `billing.fatal` (`code`) | The session was ended: `balance_exhausted` (the balance reached zero) or `billing_unavailable` (three reports in a row failed). |
| `billing.final_dropped` (`seq`) | A closing session's last report failed three times and was dropped, so that usage was not charged. One around a site restart is expected; a run of them means the site was down. |
| `session.token_expired` | A session was issued but its WebSocket never connected within a minute; the slot went back. Many of them mean clients cannot open the WebSocket (proxy upgrade headers, network). |
| `session.issue_failed` | The gateway itself failed while issuing a session (the caller got `500 internal`). The error is deliberately not logged, because it may carry what the caller sent; reproduce it locally. |

## Rollback

```bash
./deploy.sh --rollback                       # server back to the previously deployed commit, restart
ssh <server> "sudo systemctl disable --now livebridge-gateway"      # switch the service off entirely
ssh <server> "sudo rm /etc/nginx/sites-enabled/livebridge.conf && sudo nginx -t && sudo systemctl reload nginx"
```

Stopping the service only affects LiveBridge: an active call loses translation and the virtual microphone goes
silent; nothing else depends on it.

## Operating notes

- `GET /healthz` needs no credentials and reveals nothing but `{"ok":true}`.
- Logs (`journalctl -u livebridge-gateway`) contain event names, ids, counts and provider error codes — never
  transcripts, audio or tokens. This is enforced by the logger's types and covered by tests.
- `MAX_SESSIONS=1` and `MAX_SESSION_MINUTES=120` bound cost; a second client gets HTTP 429.
- `GET /v1/voices` lists the voices of the gateway's ElevenLabs account for the app's voice picker. It takes the same
  access token and shares the per-address rate limit with `POST /v1/sessions`; the list is kept for 10 minutes, and a
  stale one is served if the provider fails later. `502 voices_unavailable` means the provider refused and nothing is
  cached — usually a key without the voices read permission. Sessions still run on the configured voices.
- A service restart (deploy, OS updates) drops the call's connection for a few seconds; the app reconnects
  automatically (up to five attempts) and speech during the gap must be repeated.
- nginx `limit_conn` is 4 per address in the sample vhost.
- The per-address request limit (20 a minute, `POST /v1/sessions` and `GET /v1/voices` together) counts the address
  nginx puts in `X-Forwarded-For`; the gateway believes that header only from loopback, so nginx must overwrite it
  (the sample vhost does). Without it every caller would share one budget.
- **Check before going live:** the gateway answers `429` on `POST /v1/sessions` when a session is already active or
  the per-address rate limit is hit, and `401` for a wrong token. If the server runs fail2ban (or similar) on a
  shared access log, make sure those responses cannot ban your own address; give this vhost its own access log if
  in doubt.

## Docker alternative

```bash
docker compose -f infra/compose.yaml up --build      # reads ../.env, publishes 127.0.0.1:8201
```

Written but never built: Docker was not available where this project was developed.
