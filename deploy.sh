#!/usr/bin/env bash
# Deploys the gateway to the server:
# local commit -> git push -> server fetch + hard reset -> npm ci -> restart -> health check.
# Nothing is ever edited on the server. First-time setup (DNS, certificate, nginx vhost, systemd unit, .env):
# docs/deployment.md. First run: 2026-11-26.
set -euo pipefail

SSH_HOST="${LIVEBRIDGE_SSH_HOST:?set LIVEBRIDGE_SSH_HOST to the ssh host or alias of the server}"
REMOTE_DIR="/var/www/livebridge"
SERVICE="livebridge-gateway"
PORT=8201

case "${1:-}" in
  --status) ssh "$SSH_HOST" "systemctl is-active $SERVICE; curl -fsS http://127.0.0.1:$PORT/healthz"; exit ;;
  --logs)   ssh "$SSH_HOST" "sudo journalctl -u $SERVICE -n 80 --no-pager"; exit ;;
  --rollback)
    # Returns the server to the previous deployed commit and restarts.
    ssh "$SSH_HOST" "cd $REMOTE_DIR && git reset --hard HEAD@{1} && npm ci --omit=dev --no-audit --no-fund && sudo systemctl restart $SERVICE"
    exit ;;
  "") ;;
  *) echo "usage: ./deploy.sh [--status|--logs|--rollback]"; exit 1 ;;
esac

echo "==> local gates"
npm run -s typecheck
npm test --silent
if [ -n "$(git status --porcelain)" ]; then echo "uncommitted changes — commit first"; exit 1; fi
git ls-files --error-unmatch .env >/dev/null 2>&1 && { echo ".env is tracked by git — refusing to deploy"; exit 1; }

echo "==> push"
git push origin main

echo "==> server"
ssh "$SSH_HOST" "set -e; cd $REMOTE_DIR; git fetch origin; git reset --hard origin/main; npm ci --omit=dev --no-audit --no-fund; sudo systemctl restart $SERVICE; sleep 2; systemctl is-active $SERVICE || { sudo journalctl -u $SERVICE -n 40 --no-pager; exit 1; }"

echo "==> health"
ssh "$SSH_HOST" "curl -fsS http://127.0.0.1:$PORT/healthz"; echo
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && echo "deployed $(git rev-parse --short HEAD)"
