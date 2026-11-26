import { existsSync } from "node:fs";
import { loadConfig } from "./config.ts";
import { createLogger } from "./log.ts";
import { createFakeProviders } from "./providers/fake.ts";
import { createRealProviders } from "./providers/real.ts";
import { createGateway } from "./server.ts";
import { createSiteClient } from "./site.ts";

// Local development reads the repo-root .env; under systemd the unit's EnvironmentFile provides the same variables.
const envFile = new URL("../../../.env", import.meta.url);
if (existsSync(envFile)) process.loadEnvFile(envFile);

const log = createLogger();
let config;
try {
  config = loadConfig();
} catch (error) {
  console.error((error as Error).message);
  process.exit(1);
}

const factory =
  config.PROVIDER_MODE === "fake"
    ? createFakeProviders({
        synthSampleRate: config.synthSampleRate,
        delayMs: 40,
        // Diagnostics: FAKE_STT_SPEECH_RMS=1 makes the fake recogniser treat any non-silent input as speech.
        speechRms: Number(process.env.FAKE_STT_SPEECH_RMS) || undefined,
      })
    : createRealProviders(config, log);
// Account sessions exist only when the site's socket and the shared secret are both configured.
const site = config.accountsEnabled
  ? createSiteClient({
      socketPath: config.SITE_SOCKET_PATH,
      host: config.SITE_HOST,
      secret: config.LIVEBRIDGE_GATEWAY_SECRET,
    })
  : undefined;
const gateway = createGateway({ config, factory, log, site });
const port = await gateway.listen();
log.info("gateway.listening", {
  host: config.HOST,
  port,
  mode: config.PROVIDER_MODE,
  max_sessions: config.MAX_SESSIONS,
  accounts: config.accountsEnabled,
});
if (factory.mock)
  log.warn("gateway.mock_providers", {
    note: "placeholder text and test tones only",
  });

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    log.info("gateway.stopping", { signal });
    void gateway.close().then(() => process.exit(0));
  });
}
