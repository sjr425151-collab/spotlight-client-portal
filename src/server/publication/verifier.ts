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
