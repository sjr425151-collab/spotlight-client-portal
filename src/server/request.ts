import "server-only";

import { headers } from "next/headers";

export interface RequestMeta {
  ip: string;
  requestId: string;
  userAgent: string;
}

/**
 * Client IP for rate limiting and audit (spec 03 §17). Behind Vercel the first
 * X-Forwarded-For hop is the client; locally it is absent and "local" is used.
 */
export function clientIpFrom(get: (name: string) => string | null): string {
  const forwarded = get("x-forwarded-for")?.split(",")[0]?.trim();
  const candidate = forwarded || get("x-real-ip")?.trim() || "";
  return /^[0-9a-fA-F.:]{3,45}$/.test(candidate) ? candidate : "local";
}

export async function requestMeta(): Promise<RequestMeta> {
  const h = await headers();
  return {
    ip: clientIpFrom((name) => h.get(name)),
    requestId: h.get("x-request-id") ?? crypto.randomUUID(),
    userAgent: (h.get("user-agent") ?? "").slice(0, 300),
  };
}
