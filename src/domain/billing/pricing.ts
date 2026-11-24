/**
 * Package pricing and integer-cents money rules (spec 04 §5.1, §7, §8; OI-14, OI-15, OI-47).
 * Pure TypeScript. The database (`private.billing_packages`, `private.verified_package_prices`)
 * is authoritative; this module mirrors it for display and is checked against the
 * migration by tests/unit/wpb-contracts.test.ts.
 */

export const PACKAGE_KEYS = [
  "essential",
  "professional",
  "advanced",
  "signature",
  "prestige",
] as const;
export type PackageKey = (typeof PACKAGE_KEYS)[number];

export interface PackagePricing {
  readonly key: PackageKey;
  readonly name: string;
  readonly totalCents: number;
  readonly depositCents: number;
  readonly balanceCents: number;
}

/** 04 §5.1: maintenance is 9900 cents per month and is never reduced. */
export const MAINTENANCE_MONTHLY_CENTS = 9900;

function assertCents(value: number, label: string): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${label} must be a non-negative integer number of cents`);
  }
}

/** 04 §7: deposit = round_half_up(total x 20%) = (total x 20 + 50) div 100, in integers. */
export function depositFor(totalCents: number): number {
  assertCents(totalCents, "total");
  return Math.floor((totalCents * 20 + 50) / 100);
}

export function balanceFor(totalCents: number): number {
  return totalCents - depositFor(totalCents);
}

/** 04 §8: the initial charge is the deposit plus exactly one maintenance period. */
export function initialChargeFor(totalCents: number): number {
  return depositFor(totalCents) + MAINTENANCE_MONTHLY_CENTS;
}

const pkg = (key: PackageKey, name: string, totalCents: number): PackagePricing => ({
  key,
  name,
  totalCents,
  depositCents: depositFor(totalCents),
  balanceCents: balanceFor(totalCents),
});

export const PACKAGES: readonly PackagePricing[] = [
  pkg("essential", "Essential", 80000),
  pkg("professional", "Professional", 149500),
  pkg("advanced", "Advanced", 249500),
  pkg("signature", "Signature", 349500),
  pkg("prestige", "Prestige", 499500),
];

export function isPackageKey(value: string): value is PackageKey {
  return (PACKAGE_KEYS as readonly string[]).includes(value);
}

/** Formats integer cents as US dollars without floating-point arithmetic on the amount. */
export function formatUsd(cents: number): string {
  if (!Number.isSafeInteger(cents)) throw new RangeError("cents must be an integer");
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  const dollars = Math.trunc(abs / 100).toLocaleString("en-US");
  const rest = String(abs % 100).padStart(2, "0");
  return `${sign}$${dollars}.${rest}`;
}
