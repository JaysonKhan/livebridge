# Gateway deployment

**Nothing here has been executed.** No server was touched while building this project; the first deployment needs
the owner's explicit go-ahead. The steps assume a conventional Linux server: plain systemd services under
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
   `ssh <server> "node -v"`; installing Node 24 LTS is a server change to approve first.
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
- A service restart (deploy, OS updates) drops the call's connection for a few seconds; the app reconnects
  automatically (up to five attempts) and speech during the gap must be repeated.
- nginx `limit_conn` is 4 per address in the sample vhost.
- **Check before going live:** the gateway answers `429` on `POST /v1/sessions` when a session is already active or
  the per-address rate limit is hit, and `401` for a wrong token. If the server runs fail2ban (or similar) on a
  shared access log, make sure those responses cannot ban your own address; give this vhost its own access log if
  in doubt.

## Docker alternative

```bash
docker compose -f infra/compose.yaml up --build      # reads ../.env, publishes 127.0.0.1:8201
```

Written but never built: Docker was not available where this project was developed.
