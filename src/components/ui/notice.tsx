import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

export type NoticeTone = "info" | "success" | "danger";

const tones: Record<NoticeTone, string> = {
  info: "border-line-strong text-fg-muted",
  success: "border-success/60 text-success",
  danger: "border-danger/60 text-danger",
};

/** Inline status message. Errors use role="alert"; others are polite live regions. */
export function Notice({ tone = "info", children }: { tone?: NoticeTone; children: ReactNode }) {
  return (
    <p
      role={tone === "danger" ? "alert" : "status"}
      className={cn("rounded-control border bg-surface px-4 py-3 text-sm", tones[tone])}
    >
      {children}
    </p>
  );
}
