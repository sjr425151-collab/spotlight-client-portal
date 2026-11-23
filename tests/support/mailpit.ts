/**
 * Reads emails captured by the local Supabase stack's Mailpit (never a real mailbox).
 * Only synthetic @example.test addresses are used.
 */
const MAILPIT = process.env.MAILPIT_URL ?? "http://127.0.0.1:54324";

interface Summary {
  ID: string;
  Created: string;
  Subject: string;
}

async function search(email: string): Promise<Summary[]> {
  const response = await fetch(
    `${MAILPIT}/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`,
  );
  if (!response.ok) throw new Error(`Mailpit search failed: ${response.status}`);
  const body = (await response.json()) as { messages: Summary[] };
  return body.messages;
}

export async function clearMailbox(email: string): Promise<void> {
  await fetch(`${MAILPIT}/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`, {
    method: "DELETE",
  });
}

export async function messageCount(email: string): Promise<number> {
  return (await search(email)).length;
}

/** Waits for a new email to the address and returns its text and HTML. */
export async function waitForEmail(email: string, timeoutMs = 15_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const [latest] = await search(email);
    if (latest) {
      const response = await fetch(`${MAILPIT}/api/v1/message/${latest.ID}`);
      const message = (await response.json()) as { Text: string; HTML: string; Subject: string };
      await clearMailbox(email);
      return message;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`No email arrived for ${email}`);
}

export function codeFrom(message: { Text: string }): string {
  const match = /\b(\d{6})\b/.exec(message.Text);
  if (!match?.[1]) throw new Error("No six-digit code in email");
  return match[1];
}

export function linkFrom(message: { HTML: string }): string {
  const match = /href="([^"]+\/invite\/accept\?[^"]+)"/.exec(message.HTML);
  if (!match?.[1]) throw new Error("No invitation link in email");
  return match[1].replaceAll("&amp;", "&");
}
