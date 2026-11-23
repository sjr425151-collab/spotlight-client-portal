import type { ComponentProps } from "react";

import { cn } from "@/lib/cn";

/** Raised surface for grouped content. */
export function Card({ className, ...props }: ComponentProps<"div">) {
  return (
    <div
      className={cn("rounded-card border border-line bg-surface p-6 shadow-card sm:p-8", className)}
      {...props}
    />
  );
}
