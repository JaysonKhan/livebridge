// Structured logging that cannot carry content: fields are primitives only, so transcripts, audio, tokens and
// provider payloads have no way in unless someone passes them by name — and nothing in this service does.
export type LogFields = Record<string, string | number | boolean | undefined>;

export interface Logger {
  info(event: string, fields?: LogFields): void;
  warn(event: string, fields?: LogFields): void;
  error(event: string, fields?: LogFields): void;
}

export function createLogger(
  write: (line: string) => void = (line) => process.stdout.write(line + "\n"),
): Logger {
  const emit =
    (level: string) =>
    (event: string, fields: LogFields = {}) =>
      write(
        JSON.stringify({
          t: new Date().toISOString(),
          level,
          event,
          ...fields,
        }),
      );
  return { info: emit("info"), warn: emit("warn"), error: emit("error") };
}

export const silentLogger: Logger = { info() {}, warn() {}, error() {} };
