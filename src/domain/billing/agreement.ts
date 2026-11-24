/**
 * Agreement text constants (spec 04 §3.1; OI-17, OI-69; CLAUDE.md §5).
 *
 * The clause below is the legal-adviser-approved Authorization for Final Payment, verbatim.
 * It must never be edited or paraphrased. tests/unit/wpb-agreement.test.ts proves it equals
 * the clause in spec 04 and the database's `private.final_payment_clause()`, byte for byte.
 * No other legal text exists in this repository.
 */

export const FINAL_PAYMENT_CLAUSE = [
  "Authorization for Final Payment",
  "By accepting this agreement and submitting the initial deposit, I authorize Spotlight Marketing LLC to securely retain my payment method through Stripe for the purpose of collecting the remaining project balance.",
  "I understand that the outstanding balance, as specified in my accepted order, will become due upon my final approval of the completed website.",
  "Upon my explicit approval, I authorize Spotlight Marketing LLC to automatically charge the outstanding balance to my saved payment method without requiring a separate checkout.",
  "I understand that publication of the website is contingent upon successful payment. An itemized invoice and payment receipt will be provided electronically.",
].join("\n\n");

/** OI-69: every screen that shows the fixture carries this label. */
export const TEST_FIXTURE_LABEL = "TEST FIXTURE — NOT AN AGREEMENT";

/** The complete fixture body: the label, then only the verbatim §3.1 clause. */
export const TEST_FIXTURE_TEXT = `${TEST_FIXTURE_LABEL}\n\n${FINAL_PAYMENT_CLAUSE}`;

/** 04 §2: canonical serialization is UTF-8 with normalized line endings. */
export function canonicalText(text: string): string {
  return text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
}

export function isTestFixtureText(text: string): boolean {
  return canonicalText(text).startsWith(TEST_FIXTURE_LABEL);
}
