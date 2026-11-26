import "server-only";

/**
 * Live verification (WP-C; spec 06 §9). The server fetches the production URL and reads
 * the served build identifier from the `x-build-id` response header or a
 * `<meta name="build-id" content="...">` tag; the database compares it with the authorized
 * release's commit SHA. `fetch` is injected so tests never reach the network. In R1 the
 * request is made only when staff press "Verify live" for a recorded deployment.
 */
export interface LiveObservation {
  servedBuildId: string | null;
  httpOk: boolean;
  tlsOk: boolean;
  keyPagesOk: boolean;
  formsOk: boolean;
}

type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

export async function observeLiveSite(
  productionUrl: string,
  fetchImpl: Fetch = fetch,
): Promise<LiveObservation> {
  const failed: LiveObservation = {
    servedBuildId: null,
    httpOk: false,
    tlsOk: false,
    keyPagesOk: false,
    formsOk: false,
  };
  let url: URL;
  try {
    url = new URL(productionUrl);
  } catch {
    return failed;
  }
  if (url.protocol !== "https:") return failed;
  try {
    const response = await fetchImpl(url.toString(), {
      redirect: "follow",
      signal: AbortSignal.timeout(10_000),
    });
    const html = (await response.text()).slice(0, 500_000);
    const meta = /<meta\s+name=["']build-id["']\s+content=["']([^"']{1,100})["']/i.exec(html)?.[1];
    const servedBuildId = response.headers.get("x-build-id") ?? meta ?? null;
    // A completed HTTPS fetch implies a certificate the runtime trusts.
    return {
      servedBuildId,
      httpOk: response.status === 200,
      tlsOk: true,
      keyPagesOk: response.ok && html.length > 0,
      formsOk: /<form[\s>]/i.test(html),
    };
  } catch {
    return failed;
  }
}

/** Observes the production URL of a recorded deployment. */
export type LiveVerifier = (productionUrl: string) => Promise<LiveObservation>;

/**
 * Local development and test only (AUTH-008 I-2, seam (b)): an injected `fetch` stub, so a
 * synthetic deployment can be verified without any network request. It answers only for a
 * host in the reserved `.test` domain (RFC 6761) and throws for any other host, which
 * `observeLiveSite` records as a failed observation. The served build identifier is the
 * host's first label when that label is a 40-character lowercase hexadecimal commit SHA (for
 * example `https://<sha>.live.example.test/`); otherwise the page serves none, so the
 * verification fails.
 */
export const mockLiveFetch = async (url: string): Promise<Response> => {
  const host = new URL(url).hostname;
  if (!host.endsWith(".test")) {
    throw new TypeError("The mock live verifier serves only reserved .test hosts");
  }
  const sha = /^([0-9a-f]{40})\./.exec(host)?.[1];
  const meta = sha ? `<meta name="build-id" content="${sha}">` : "";
  const html =
    `<!doctype html><html lang="en"><head>${meta}<title>Synthetic live site</title></head>` +
    `<body><main><h1>Synthetic live site</h1><form action="/contact"></form></main></body></html>`;
  return new Response(html, { status: 200, headers: { "content-type": "text/html" } });
};

/**
 * The live verifier for an environment, the same pattern as `scannerFor`. Only an affirmative
 * `development` or `test` classification selects the stub; every other value, including a
 * missing or unknown one, `preview`, `staging` and `production`, selects the real verifier,
 * which is unchanged.
 */
export function verifierFor(appEnv: string): LiveVerifier {
  if (appEnv === "development" || appEnv === "test") {
    return (productionUrl) => observeLiveSite(productionUrl, mockLiveFetch);
  }
  return (productionUrl) => observeLiveSite(productionUrl);
}
