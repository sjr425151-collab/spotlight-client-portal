import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import type { ReactNode } from "react";

import { SiteFooter } from "@/components/site/site-footer";
import { SiteHeader } from "@/components/site/site-header";
import { env } from "@/config/env";
import { site } from "@/config/site";
import { colors } from "@/design/tokens";

import "./globals.css";

// Fonts are self-hosted (SIL OFL 1.1, see src/app/fonts/LICENSE-*): no third-party
// requests at runtime or build time.
const inter = localFont({
  src: "./fonts/inter-latin-wght-normal.woff2",
  variable: "--font-inter",
  weight: "100 900",
  display: "swap",
});

const montserrat = localFont({
  src: [
    { path: "./fonts/montserrat-latin-wght-normal.woff2", style: "normal", weight: "100 900" },
    { path: "./fonts/montserrat-latin-wght-italic.woff2", style: "italic", weight: "100 900" },
  ],
  variable: "--font-montserrat",
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL(env.NEXT_PUBLIC_SITE_URL),
  title: {
    default: site.name,
    template: `%s · ${site.name}`,
  },
  description: site.description,
  applicationName: site.name,
  // No favicon is shipped until an Owner-approved icon variant exists (DEP-08).
  // An empty data URI prevents a 404 request for /favicon.ico.
  icons: { icon: [{ url: "data:," }] },
};

export const viewport: Viewport = {
  themeColor: colors.canvas,
  colorScheme: "dark",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en-US" className={`${inter.variable} ${montserrat.variable}`}>
      <body className="flex min-h-dvh flex-col">
        <a
          href="#main"
          className="sr-only rounded-control bg-fg px-4 py-2 font-medium text-canvas focus:not-sr-only focus:fixed focus:top-4 focus:left-4 focus:z-50"
        >
          Skip to content
        </a>
        <SiteHeader />
        <main id="main" className="flex-1">
          {children}
        </main>
        <SiteFooter />
      </body>
    </html>
  );
}
