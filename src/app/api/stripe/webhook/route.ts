import { NextResponse } from "next/server";

import { env } from "@/config/env";
import { receiveStripeWebhook } from "@/server/services/billing";
import { getStripeGateway, type StripeGateway } from "@/server/stripe";

/**
 * Stripe webhook endpoint (spec 04 §11, §17 #4). Authenticated by the Stripe signature on
 * the raw body, never by a session. Fails closed (503) when no signing secret is configured.
 * The event is acknowledged only after it is stored durably.
 */
export const dynamic = "force-dynamic";

const MAX_BODY_BYTES = 256 * 1024;

export async function POST(request: Request) {
  const secret = env.STRIPE_WEBHOOK_SECRET;
  if (!secret)
    return NextResponse.json({ received: false, error: "not_configured" }, { status: 503 });

  const rawBody = await request.text();
  if (Buffer.byteLength(rawBody, "utf8") > MAX_BODY_BYTES) {
    return NextResponse.json({ received: false, error: "too_large" }, { status: 413 });
  }
  let gateway: StripeGateway | null = null;
  try {
    gateway = await getStripeGateway();
  } catch {
    // No gateway configured: the event is still stored; card lookups wait for the job.
  }
  const result = await receiveStripeWebhook(
    rawBody,
    request.headers.get("stripe-signature"),
    secret,
    gateway,
  );
  return NextResponse.json(result.body, {
    status: result.status,
    headers: { "Cache-Control": "no-store" },
  });
}
