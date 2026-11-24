import { z } from "zod";

/**
 * Intake fields (WP-C; spec 05 §3). The field list and required flags are [PROPOSED] in
 * 05 §3 for Owner refinement. The keys mirror `private.intake_allowed_keys()` and
 * `private.intake_required_keys()`; `tests/unit/wpc-intake.test.ts` checks that they agree.
 * Logos, photos, and brand guidelines are uploads (05 §4), not intake fields.
 */

export type IntakeFieldKind = "text" | "textarea" | "list" | "choice";

export interface IntakeField {
  readonly key: string;
  readonly label: string;
  readonly kind: IntakeFieldKind;
  readonly required: boolean;
  readonly hint?: string;
  readonly choices?: readonly { value: string; label: string }[];
}

export const INTAKE_FIELDS: readonly IntakeField[] = [
  { key: "business_legal_name", label: "Business legal name", kind: "text", required: true },
  { key: "business_display_name", label: "Business display name", kind: "text", required: true },
  { key: "contact_phone", label: "Contact phone", kind: "text", required: true },
  { key: "contact_email", label: "Contact email", kind: "text", required: true },
  { key: "address", label: "Business address", kind: "textarea", required: true },
  {
    key: "service_areas",
    label: "Service areas",
    kind: "list",
    required: true,
    hint: "One per line.",
  },
  {
    key: "services_offered",
    label: "Services offered",
    kind: "list",
    required: true,
    hint: "One per line.",
  },
  { key: "brand_guidelines_notes", label: "Brand notes", kind: "textarea", required: false },
  {
    key: "style_references",
    label: "Websites you like",
    kind: "list",
    required: false,
    hint: "One address per line.",
  },
  { key: "color_preferences", label: "Color preferences", kind: "text", required: false },
  {
    key: "pages_wanted",
    label: "Pages you want",
    kind: "list",
    required: false,
    hint: "One per line.",
  },
  {
    key: "domain_status",
    label: "Domain",
    kind: "choice",
    required: true,
    choices: [
      { value: "existing", label: "I already have a domain" },
      { value: "needs_domain", label: "I need a domain" },
    ],
  },
  {
    key: "existing_domain",
    label: "Existing domain",
    kind: "text",
    required: false,
    hint: "Required if you already have one.",
  },
  { key: "additional_notes", label: "Anything else", kind: "textarea", required: false },
];

export const INTAKE_ALLOWED_KEYS = INTAKE_FIELDS.map((f) => f.key);
export const INTAKE_REQUIRED_KEYS = INTAKE_FIELDS.filter((f) => f.required).map((f) => f.key);

const listItem = z.string().trim().min(1).max(300);
const textValue = z.string().trim().max(2000);

/** A draft: any subset of known fields, each within the database bounds. */
export const intakeDraftSchema = z
  .object(
    Object.fromEntries(
      INTAKE_FIELDS.map((f) => [
        f.key,
        (f.kind === "list"
          ? z.array(listItem).max(50)
          : f.kind === "choice"
            ? z.enum(f.choices!.map((c) => c.value) as [string, ...string[]])
            : textValue
        ).optional(),
      ]),
    ),
  )
  .strict();
export type IntakeContent = z.infer<typeof intakeDraftSchema>;

/** Submission requires every required field, and the domain when one exists. */
export function missingRequiredFields(content: Record<string, unknown>): string[] {
  const missing = INTAKE_REQUIRED_KEYS.filter((key) => {
    const value = content[key];
    return Array.isArray(value) ? value.length === 0 : typeof value !== "string" || value.trim() === "";
  });
  if (
    content.domain_status === "existing" &&
    (typeof content.existing_domain !== "string" || content.existing_domain.trim() === "")
  ) {
    missing.push("existing_domain");
  }
  return missing;
}

/** Builds stored content from form fields; empty values are omitted. */
export function intakeFromForm(get: (key: string) => string | null): IntakeContent {
  const content: Record<string, unknown> = {};
  for (const field of INTAKE_FIELDS) {
    const raw = (get(field.key) ?? "").trim();
    if (!raw) continue;
    content[field.key] =
      field.kind === "list"
        ? raw
            .split(/\r?\n/)
            .map((line) => line.trim())
            .filter(Boolean)
        : raw;
  }
  return intakeDraftSchema.parse(content);
}
