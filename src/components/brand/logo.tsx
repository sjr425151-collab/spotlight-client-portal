import Image from "next/image";

import { cn } from "@/lib/cn";

/**
 * Official Spotlight Marketing logo (Owner-confirmed master, 07 §10.1).
 * Source file: public/brand/spotlight-marketing-logo.jpg
 * SHA-256 6cc6edb39da3a8a6e5412d14989c590039632aff85e4114812c21a2ce8b2bd3c
 *
 * The artwork is never redrawn, recolored, or stretched. Its intrinsic ratio (597 x 335)
 * is preserved at every size. The master is a JPEG on a black field, so it is composited
 * with `mix-blend-mode: screen`: black pixels take the page color and the white wordmark
 * and glow are unchanged. Use it only on the dark canvas until an Owner-approved
 * transparent or light-background variant exists (DEP-08).
 *
 * The master's glow haze is cropped at its right edge, which shows as a faint straight
 * line. A narrow horizontal edge fade (outer 4-5% of the width, clear of the wordmark and
 * of the arc, whose outermost point is about 92% across) hides that crop line. The artwork
 * itself is unchanged.
 *
 * OI-49 (Owner-approved 2026-11-23): the blend and edge fade are a TEMPORARY presentation
 * treatment. The master file must never be edited; tests/unit/brand.test.ts pins its
 * SHA-256. Remove both treatments when an approved transparent/vector master exists (DEP-08).
 */
// Mask gradients use alpha only; `black` here means "fully visible", not a page color.
const edgeFade = "linear-gradient(to right, transparent 0%, black 4%, black 95%, transparent 100%)";
export const LOGO_WIDTH = 597;
export const LOGO_HEIGHT = 335;

export function Logo({ className, priority = false }: { className?: string; priority?: boolean }) {
  return (
    <Image
      src="/brand/spotlight-marketing-logo.jpg"
      alt="Spotlight Marketing"
      width={LOGO_WIDTH}
      height={LOGO_HEIGHT}
      priority={priority}
      sizes="(min-width: 640px) 160px, 128px"
      className={cn("h-auto mix-blend-screen select-none", className)}
      style={{ maskImage: edgeFade, WebkitMaskImage: edgeFade }}
    />
  );
}
