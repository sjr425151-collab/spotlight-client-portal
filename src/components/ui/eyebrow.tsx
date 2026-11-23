import type { ComponentProps } from "react";

import { cn } from "@/lib/cn";

/** Small, widely tracked uppercase label, echoing the "MARKETING" line of the logo. */
export function Eyebrow({ className, ...props }: ComponentProps<"p">) {
  return (
    <p
      className={cn(
        "font-display text-xs font-semibold tracking-eyebrow text-accent uppercase",
        className,
      )}
      {...props}
    />
  );
}
