// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { cn } from "@/lib/cn";

afterEach(cleanup);

describe("Button", () => {
  it("defaults to type=button so it never submits a form by accident", () => {
    render(<Button>Save</Button>);
    expect(screen.getByRole("button", { name: "Save" })).toHaveProperty("type", "button");
  });

  it("exposes the disabled state to assistive technology", () => {
    render(<Button disabled>Continue</Button>);
    expect(screen.getByRole("button", { name: "Continue" })).toHaveProperty("disabled", true);
  });
});

describe("TextField", () => {
  it("associates the visible label with the input", () => {
    render(<TextField label="Business name" />);
    expect(screen.getByLabelText("Business name").tagName).toBe("INPUT");
  });

  it("announces hint and error text and marks the input invalid", () => {
    render(<TextField label="Website" hint="Include https://" error="Enter a valid URL." />);
    const input = screen.getByRole("textbox", { name: "Website" });
    expect(input.getAttribute("aria-invalid")).toBe("true");
    const describedBy = (input.getAttribute("aria-describedby") ?? "").split(" ");
    const descriptions = describedBy.map((id) => document.getElementById(id)?.textContent);
    expect(descriptions).toEqual(["Include https://", "Enter a valid URL."]);
  });

  it("is not marked invalid without an error", () => {
    render(<TextField label="Email" />);
    expect(screen.getByRole("textbox", { name: "Email" }).hasAttribute("aria-invalid")).toBe(false);
  });
});

describe("cn", () => {
  it("joins truthy class names only", () => {
    expect(cn("a", false, null, undefined, "b")).toBe("a b");
  });
});
