import "server-only";

import { parseServerEnv } from "./env-schema";

/**
 * Validated server configuration. Importing this module from client code fails the
 * build (`server-only`). Invalid configuration fails closed at startup.
 */
export const env = parseServerEnv(process.env);
