function emit(level: "info" | "warn" | "error", msg: string, meta?: object) {
  const line = `${new Date().toISOString()} ${level.toUpperCase()} ${msg}${meta ? " " + JSON.stringify(meta) : ""}`;
  (level === "info" ? console.log : level === "warn" ? console.warn : console.error)(line);
}

export const log = {
  info: (msg: string, meta?: object) => emit("info", msg, meta),
  warn: (msg: string, meta?: object) => emit("warn", msg, meta),
  error: (msg: string, meta?: object) => emit("error", msg, meta),
};
