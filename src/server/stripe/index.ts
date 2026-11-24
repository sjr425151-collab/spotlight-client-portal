import "server-only";

import { env } from "@/config/env";

import { StripeGatewayUnavailableError, type StripeGateway } from "./gateway";
import { MockStripeGateway } from "./mock-gateway";

/**
 * The only way server code obtains a Stripe gateway. Fails closed: with
 * `STRIPE_GATEWAY=disabled` (the default) there is no gateway, and the environment schema
 * allows `mock` only in development and test. A real gateway is added only under AUTH-002.
 */
// One mock per server process. Next.js can load this module once per route bundle, so the
// instance lives on globalThis: a Checkout created by a server action must be visible to the
// webhook route's card lookup, as it would be at Stripe. Mock state only; never a credential.
const holder = globalThis as typeof globalThis & {
  __spotlightMockStripeGateway?: MockStripeGateway;
};

export function getStripeGateway(): StripeGateway {
  if (env.STRIPE_GATEWAY === "mock") {
    holder.__spotlightMockStripeGateway ??= new MockStripeGateway();
    return holder.__spotlightMockStripeGateway;
  }
  throw new StripeGatewayUnavailableError();
}

export { StripeGatewayUnavailableError } from "./gateway";
export type { StripeGateway } from "./gateway";
