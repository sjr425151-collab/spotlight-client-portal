import { createHash, randomBytes } from "node:crypto";

import { computeSignature } from "@/server/stripe/webhook-signature";

/**
 * Synthetic Stripe-format events signed with a test-only secret generated per run (OI-63).
 * Nothing here is a Stripe credential or a Stripe request; CI never holds a Stripe secret.
 * Same construction as tests/integration/wpb-billing.test.ts.
 */
export function testWebhookSecret(label: string): string {
  const seed = `${label}-${Date.now()}-${randomBytes(8).toString("hex")}`;
  return `whsec_${createHash("sha256").update(seed).digest("hex").slice(0, 32)}`;
}

export type SignedEvent = { id: string; rawBody: string; header: string };

export function signedEvent(
  secret: string,
  type: string,
  object: Record<string, unknown>,
  id = `evt_${randomBytes(10).toString("hex")}`,
): SignedEvent {
  const now = Math.floor(Date.now() / 1000);
  const rawBody = JSON.stringify({
    id,
    object: "event",
    type,
    api_version: "2026-09-30.endive",
    livemode: false,
    created: now,
    data: { object },
  });
  return { id, rawBody, header: `t=${now},v1=${computeSignature(secret, now, rawBody)}` };
}
