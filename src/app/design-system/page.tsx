import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { Container } from "@/components/layout/container";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Eyebrow } from "@/components/ui/eyebrow";
import { TextField } from "@/components/ui/field";
import { env } from "@/config/env";
import { isDesignSystemEnabled } from "@/config/env-schema";
import { colors, contrastRatio, type ColorToken } from "@/design/tokens";

export const metadata: Metadata = {
  title: "Design system",
  robots: { index: false, follow: false },
};

const swatches: ReadonlyArray<{ token: ColorToken; on: ColorToken }> = [
  { token: "canvas", on: "fg" },
  { token: "surface", on: "fg" },
  { token: "surface-raised", on: "fg" },
  { token: "line-strong", on: "fg" },
  { token: "fg", on: "canvas" },
  { token: "fg-muted", on: "canvas" },
  { token: "fg-subtle", on: "canvas" },
  { token: "accent", on: "canvas" },
  { token: "danger", on: "canvas" },
  { token: "success", on: "canvas" },
  { token: "warning", on: "canvas" },
];

/**
 * Internal reference for the Phase 1 design foundation. Never served in production
 * (`isDesignSystemEnabled`), and excluded from indexing.
 */
export default function DesignSystemPage() {
  if (!isDesignSystemEnabled(env.APP_ENV)) notFound();

  return (
    <Container className="flex flex-col gap-16 py-16">
      <header>
        <Eyebrow>Internal reference</Eyebrow>
        <h1 className="mt-4 font-display text-3xl font-bold tracking-tight text-fg sm:text-4xl">
          Design system
        </h1>
        <p className="mt-4 max-w-2xl text-fg-muted">
          Provisional tokens and primitives for the portal. Final brand colors and typography
          require Owner approval before production.
        </p>
      </header>

      <section aria-labelledby="colors-heading">
        <h2 id="colors-heading" className="font-display text-xl font-semibold text-fg">
          Color
        </h2>
        <ul className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
          {swatches.map(({ token, on }) => (
            <li key={token} className="overflow-hidden rounded-card border border-line">
              <div
                className="flex h-20 items-end p-3 text-sm font-medium"
                style={{ backgroundColor: colors[token], color: colors[on] }}
              >
                Aa {contrastRatio(colors[on], colors[token]).toFixed(1)}:1
              </div>
              <div className="bg-surface p-3 text-sm">
                <p className="font-medium text-fg">{token}</p>
                <p className="font-mono text-fg-subtle">{colors[token]}</p>
              </div>
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="type-heading">
        <h2 id="type-heading" className="font-display text-xl font-semibold text-fg">
          Typography
        </h2>
        <div className="mt-6 flex flex-col gap-4">
          <p className="font-display text-5xl font-bold tracking-tight text-fg">
            Display, Montserrat
          </p>
          <p className="font-display text-3xl font-bold tracking-tight text-fg italic">
            Display italic
          </p>
          <p className="text-lg text-fg">Body large, Inter. The quick brown fox.</p>
          <p className="text-base text-fg-muted">Body. Secondary text for supporting detail.</p>
          <p className="text-sm text-fg-subtle">Caption. Tertiary text for metadata.</p>
          <Eyebrow>Eyebrow label</Eyebrow>
        </div>
      </section>

      <section aria-labelledby="buttons-heading">
        <h2 id="buttons-heading" className="font-display text-xl font-semibold text-fg">
          Buttons
        </h2>
        <div className="mt-6 flex flex-wrap items-center gap-4">
          <Button>Primary</Button>
          <Button variant="secondary">Secondary</Button>
          <Button variant="ghost">Ghost</Button>
          <Button size="lg">Large primary</Button>
          <Button disabled>Disabled</Button>
        </div>
      </section>

      <section aria-labelledby="fields-heading">
        <h2 id="fields-heading" className="font-display text-xl font-semibold text-fg">
          Form fields
        </h2>
        <div className="mt-6 grid max-w-3xl gap-6 sm:grid-cols-2">
          <TextField label="Business name" name="example-business" autoComplete="organization" />
          <TextField
            label="Email address"
            name="example-email"
            type="email"
            autoComplete="email"
            hint="We will only use this for project updates."
            required
          />
          <TextField
            label="Website"
            name="example-website"
            defaultValue="not a url"
            error="Enter a full web address, such as https://example.com."
          />
          <TextField
            label="Disabled field"
            name="example-disabled"
            disabled
            defaultValue="Locked"
          />
        </div>
      </section>

      <section aria-labelledby="cards-heading">
        <h2 id="cards-heading" className="font-display text-xl font-semibold text-fg">
          Cards
        </h2>
        <div className="mt-6 grid gap-5 sm:grid-cols-2">
          <Card>
            <h3 className="font-display text-lg font-semibold text-fg">Card title</h3>
            <p className="mt-2 text-sm text-fg-muted">
              Cards group related content on a raised surface.
            </p>
          </Card>
          <Card className="shadow-glow">
            <h3 className="font-display text-lg font-semibold text-fg">Highlighted card</h3>
            <p className="mt-2 text-sm text-fg-muted">The eclipse glow marks emphasis.</p>
          </Card>
        </div>
      </section>
    </Container>
  );
}
