import { Container } from "@/components/layout/container";
import { site } from "@/config/site";

export function SiteFooter() {
  const year = new Date().getFullYear();

  return (
    <footer className="border-t border-line/70">
      <Container className="flex flex-col gap-3 py-10 text-sm text-fg-subtle sm:flex-row sm:items-center sm:justify-between">
        <p>
          © {year} {site.organization}. All rights reserved.
        </p>
        <a
          href={site.agencyUrl}
          className="rounded-sm text-fg-muted underline-offset-4 transition-colors hover:text-fg hover:underline"
        >
          {site.agencyLabel}
        </a>
      </Container>
    </footer>
  );
}
