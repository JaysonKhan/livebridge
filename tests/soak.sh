#!/usr/bin/env bash
# Soak test: one long headless session on real audio hardware against a gateway running FAKE providers.
# It checks LiveBridge's own stability (queues, memory, sockets, latency drift) — not any real provider.
#
#   tests/soak.sh [minutes=60]
#
# Plays at -70 dB on the default output device (inaudible), uses a generated tone instead of the microphone, and
# writes bench-out/soak-{session.txt,gateway.log,rss.csv,summary.json}.
set -euo pipefail

MINUTES="${1:-60}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/bench-out"
PORT=8209
LB="$ROOT/apps/desktop/native/LiveBridgeAudio/.build/debug/lbaudio"
[ -x "$LB" ] || { echo "build the CLI first: (cd apps/desktop/native/LiveBridgeAudio && swift build)"; exit 1; }
mkdir -p "$OUT"

TOKEN="soak-$(openssl rand -hex 24)"
OUTPUT_UID="$("$LB" devices | python3 -c 'import json,sys; print(next(d["uid"] for d in json.load(sys.stdin) if d["isDefaultOutput"]))')"
TURNS=$(( MINUTES * 600 / 33 ))   # a turn takes about 3.3 s: 1 s held, ~1.4 s of audio, settle time

PROVIDER_MODE=fake GATEWAY_ACCESS_TOKEN="$TOKEN" PORT="$PORT" MAX_SESSION_MINUTES=$(( MINUTES + 30 )) \
  node "$ROOT/services/gateway/src/main.ts" > "$OUT/soak-gateway.log" 2>&1 &
GATEWAY=$!
trap 'kill "$GATEWAY" 2>/dev/null || true' EXIT
sleep 1.5

"$LB" session --gateway "http://127.0.0.1:$PORT" --token "$TOKEN" --synthetic-mic --virtual-mic "$OUTPUT_UID" \
  --headphones unused --gain-db -70 --turns "$TURNS" --hold 1.0 > "$OUT/soak-session.txt" 2>&1 &
ENGINE=$!

echo "minute,gateway_rss_kb,engine_rss_kb" > "$OUT/soak-rss.csv"
START=$(date +%s)
while kill -0 "$ENGINE" 2>/dev/null; do
  echo "$(( ($(date +%s) - START) / 60 )),$(ps -o rss= -p "$GATEWAY" | tr -d ' '),$(ps -o rss= -p "$ENGINE" | tr -d ' ')" >> "$OUT/soak-rss.csv"
  sleep 60
done
wait "$ENGINE" || true
ELAPSED=$(( $(date +%s) - START ))

python3 - "$OUT" "$TURNS" "$ELAPSED" <<'EOF'
import csv, json, sys
out, planned, elapsed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
text = open(f"{out}/soak-session.txt").read()
summary = json.loads(text.split("--- summary ---")[1]) if "--- summary ---" in text else {}
e2e = summary.get("endToEndMs", [])
def pct(values, p):
    values = sorted(values)
    return values[min(len(values) - 1, max(0, round(p / 100 * len(values)) - 1))] if values else None
rows = list(csv.DictReader(open(f"{out}/soak-rss.csv")))
rss = lambda key: [int(r[key]) for r in rows if r[key]]
log = [json.loads(line) for line in open(f"{out}/soak-gateway.log") if line.startswith("{")]
result = {
    "minutes": round(elapsed / 60, 1),
    "turnsPlanned": planned,
    "turnsAudible": len(e2e),
    "errors": summary.get("errors", ["no summary — the session did not finish cleanly"]),
    "finalState": summary.get("finalState"),
    "e2eMs_first100": {"p50": pct(e2e[:100], 50), "p95": pct(e2e[:100], 95)},
    "e2eMs_last100": {"p50": pct(e2e[-100:], 50), "p95": pct(e2e[-100:], 95)},
    "e2eMs_all": {"p50": pct(e2e, 50), "p95": pct(e2e, 95), "p99": pct(e2e, 99), "max": max(e2e) if e2e else None},
    "gatewayRssKb": {"first": rss("gateway_rss_kb")[:1], "last": rss("gateway_rss_kb")[-1:], "max": max(rss("gateway_rss_kb") or [0])},
    "engineRssKb": {"first": rss("engine_rss_kb")[:1], "last": rss("engine_rss_kb")[-1:], "max": max(rss("engine_rss_kb") or [0])},
    "gatewayLogLines": len(log),
    "gatewayWarningsOrErrors": sorted({e["event"] for e in log if e.get("level") != "info" and e.get("event") != "gateway.mock_providers"}),
}
json.dump(result, open(f"{out}/soak-summary.json", "w"), indent=2)
print(json.dumps(result, indent=2))
EOF
