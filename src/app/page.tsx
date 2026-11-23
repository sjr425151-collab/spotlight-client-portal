import { Container } from "@/components/layout/container";
import { Card } from "@/components/ui/card";
import { Eyebrow } from "@/components/ui/eyebrow";
import { site } from "@/config/site";

const journey = [
  {
    title: "Agreement and deposit",
    body: "Review your services agreement and project summary, then confirm and pay securely.",
  },
  {
    title: "Onboarding",
    body: "Share your business details, brand assets, and preferences in one organized place.",
  },
  {
    title: "Preview and approval",
    body: "Review each preview release of your website and approve it when it is right.",
  },
  {
    title: "Launch",
    body: "Your site is published only after every quality, security, and payment check passes.",
  },
] as const;

export default function HomePage() {
  return (
    <>
      <section className="relative isolate overflow-hidden">
        <EclipseGlow />
        <Container className="flex flex-col gap-10 pt-20 pb-24 sm:pt-28 sm:pb-32 lg:flex-row lg:items-end lg:justify-between">
          <div className="max-w-2xl">
            <Eyebrow>{site.shortName}</Eyebrow>
            <h1 className="mt-6 font-display text-4xl leading-[1.05] font-bold tracking-tight text-balance text-fg sm:text-6xl">
              Your website project,{" "}
              <span className="text-fg-muted italic">in one secure place.</span>
            </h1>
            <p className="mt-6 max-w-xl text-lg leading-relaxed text-pretty text-fg-muted">
              Agreements, onboarding, previews, and launch for your Spotlight Marketing website,
              managed together from the first signature to go-live.
            </p>
          </div>

          <Card className="max-w-sm shrink-0 bg-surface/80 backdrop-blur">
            <div className="flex items-start gap-4">
              <LockIcon />
              <div>
                <h2 className="font-display text-base font-semibold text-fg">
                  Access is by invitation
                </h2>
                <p className="mt-2 text-sm leading-relaxed text-fg-muted">
                  When your project begins, you will receive a secure sign-in link by email. No
                  password is needed.
                </p>
              </div>
            </div>
          </Card>
        </Container>
      </section>

      <section aria-labelledby="journey-heading" className="border-t border-line/70 bg-surface/40">
        <Container className="py-20 sm:py-24">
          <Eyebrow>How it works</Eyebrow>
          <h2
            id="journey-heading"
            className="mt-4 max-w-2xl font-display text-2xl font-bold tracking-tight text-fg sm:text-3xl"
          >
            Every step of your project, clearly in view.
          </h2>
          <ol className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
            {journey.map((step, index) => (
              <li key={step.title}>
                <Card className="h-full p-6 sm:p-6">
                  <p
                    className="font-display text-sm font-semibold tracking-eyebrow text-accent"
                    aria-hidden="true"
                  >
                    {String(index + 1).padStart(2, "0")}
                  </p>
                  <h3 className="mt-4 font-display text-lg font-semibold text-fg">{step.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-fg-muted">{step.body}</p>
                </Card>
              </li>
            ))}
          </ol>
        </Container>
      </section>
    </>
  );
}

/** Decorative arc echoing the logo's eclipse. Purely visual: hidden from assistive tech. */
function EclipseGlow() {
  return (
    <div aria-hidden="true" className="pointer-events-none absolute inset-0 -z-10">
      <div className="absolute -top-56 -right-40 size-[38rem] rounded-full border border-accent/25 shadow-glow motion-safe:animate-eclipse sm:-top-64 sm:-right-24 sm:size-[46rem]" />
      <div className="absolute -top-56 -right-40 size-[38rem] rounded-full bg-[radial-gradient(circle_at_30%_70%,color-mix(in_srgb,var(--color-accent)_12%,transparent),transparent_60%)] sm:-top-64 sm:-right-24 sm:size-[46rem]" />
    </div>
  );
}

function LockIcon() {
  return (
    <span className="flex size-10 shrink-0 items-center justify-center rounded-full border border-line-strong bg-surface-raised text-accent">
      <svg
        aria-hidden="true"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="size-5"
      >
        <rect x="4.5" y="10.5" width="15" height="10" rx="2" />
        <path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" />
      </svg>
    </span>
  );
}
