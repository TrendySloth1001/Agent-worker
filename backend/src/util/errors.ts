import type { NextFunction, Request, Response } from "express";
import { ZodError } from "zod";
import { log } from "./logger.js";
import { USER_MSG, userMessage } from "./userMessages.js";

export class AppError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public retryable = false,
  ) {
    super(message);
    this.name = "AppError";
  }
}

/** The JSON error body. A message unfit for users (upstream text, codes, names) is replaced by a friendly line for its code. */
export function errorBody(code: string, message: string, retryable = false) {
  return { error: { code, message: userMessage(code, message), retryable } };
}

// Express requires the 4-arg signature to treat this as an error handler.
export function errorMiddleware(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  let status = 500;
  let code = "internal";
  let message: string = USER_MSG.generic;
  let retryable = false;

  if (err instanceof AppError) {
    ({ status, code, message, retryable } = err);
  } else if (err instanceof ZodError) {
    status = 400;
    code = "bad_request";
    message = USER_MSG.badRequest;
  } else if (err && typeof err === "object" && (err as { type?: string }).type === "entity.too.large") {
    status = 413;
    code = "payload_too_large";
    message = "That's too large to send.";
  } else if (err && typeof err === "object" && (err as { type?: string }).type === "entity.parse.failed") {
    status = 400;
    code = "bad_request";
    message = USER_MSG.badRequest;
  } else {
    log.error("unhandled error", { message: err instanceof Error ? err.message.slice(0, 200) : String(err).slice(0, 200) });
  }

  if (userMessage(code, message) !== message) log.info("error text hidden from user", { code, status, message: message.slice(0, 200) });
  if (res.headersSent) {
    res.end();
    return;
  }
  res.status(status).json(errorBody(code, message, retryable));
}
