import { useId, type ComponentProps } from "react";

import { cn } from "@/lib/cn";

export type TextFieldProps = Omit<ComponentProps<"input">, "id"> & {
  label: string;
  /** Helper text shown below the input and announced with it. */
  hint?: string;
  /** Validation message. Marks the input invalid and is announced to assistive tech. */
  error?: string;
  id?: string;
};

/**
 * Labelled text input with accessible hint and error wiring. Labels are always
 * visible: placeholders are never used as labels.
 */
export function TextField({
  label,
  hint,
  error,
  id: providedId,
  className,
  required,
  ...props
}: TextFieldProps) {
  const generatedId = useId();
  const id = providedId ?? generatedId;
  const hintId = hint ? `${id}-hint` : undefined;
  const errorId = error ? `${id}-error` : undefined;
  const describedBy = [hintId, errorId].filter(Boolean).join(" ") || undefined;

  return (
    <div className={cn("flex flex-col gap-2", className)}>
      <label htmlFor={id} className="text-sm font-medium text-fg">
        {label}
        {required ? (
          <span className="ml-1 text-fg-subtle" aria-hidden="true">
            *
          </span>
        ) : null}
      </label>
      <input
        id={id}
        required={required}
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy}
        className={cn(
          "h-11 rounded-control border bg-surface px-3.5 text-base text-fg sm:text-sm",
          "placeholder:text-fg-subtle transition-colors duration-150",
          "hover:border-fg-subtle disabled:cursor-not-allowed disabled:opacity-50",
          error ? "border-danger" : "border-line-strong",
        )}
        {...props}
      />
      {hint ? (
        <p id={hintId} className="text-sm text-fg-subtle">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={errorId} className="text-sm text-danger">
          {error}
        </p>
      ) : null}
    </div>
  );
}
