// @vitest-environment jsdom
import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import {
  AcceptanceForm,
  AgreementDocument,
  OrderSummaryCard,
} from "@/components/billing/agreement-acceptance";
import { TEST_FIXTURE_LABEL, TEST_FIXTURE_TEXT } from "@/domain/billing/agreement";

afterEach(cleanup);

const noop = () => undefined;

describe("AcceptanceForm (04 §3; T-AGR-01, T-AGR-06)", () => {
  it("renders two separate acceptance checkboxes, both unchecked by default and required", () => {
    render(
      <AcceptanceForm
        action={noop}
        projectId="p"
        orderSummaryId="o"
        businessLegalName="Biz LLC"
        isTestFixture={false}
      />,
    );
    const boxes = screen.getAllByRole("checkbox");
    expect(boxes).toHaveLength(2);
    for (const box of boxes) {
      expect((box as HTMLInputElement).checked).toBe(false);
      expect((box as HTMLInputElement).defaultChecked).toBe(false);
      expect((box as HTMLInputElement).required).toBe(true);
    }
    expect(boxes.map((b) => (b as HTMLInputElement).name)).toEqual([
      "accepted",
      "authorityConfirmed",
    ]);
  });

  it("requires the signer's legal name, the business legal name and the title", () => {
    render(
      <AcceptanceForm
        action={noop}
        projectId="p"
        orderSummaryId="o"
        businessLegalName="Biz LLC"
        isTestFixture={false}
      />,
    );
    for (const label of ["Your full legal name", "Business legal name", "Your position or title"]) {
      expect((screen.getByLabelText(new RegExp(label)) as HTMLInputElement).required).toBe(true);
    }
  });

  it("reports the unchecked initial state to the server", () => {
    const { container } = render(
      <AcceptanceForm
        action={noop}
        projectId="p"
        orderSummaryId="o"
        businessLegalName="Biz LLC"
        isTestFixture={false}
      />,
    );
    expect(container.querySelector('input[name="checkboxDefault"]')?.getAttribute("value")).toBe(
      "unchecked",
    );
  });
});

describe("Fixture label (OI-69; T-AGR-08)", () => {
  it("labels the agreement document and the acceptance form when the version is a fixture", () => {
    render(
      <>
        <AgreementDocument versionLabel="test-fixture-1" text={TEST_FIXTURE_TEXT} isTestFixture />
        <AcceptanceForm
          action={noop}
          projectId="p"
          orderSummaryId="o"
          businessLegalName="Biz LLC"
          isTestFixture
        />
      </>,
    );
    const labels = screen.getAllByTestId("test-fixture-label");
    expect(labels).toHaveLength(2);
    for (const label of labels) expect(label.textContent).toContain(TEST_FIXTURE_LABEL);
  });

  it("shows no fixture label for a real version", () => {
    render(
      <AgreementDocument versionLabel="1.0" text="Counsel-approved text" isTestFixture={false} />,
    );
    expect(screen.queryByTestId("test-fixture-label")).toBeNull();
  });
});

describe("OrderSummaryCard (04 §4, §8)", () => {
  it("shows the snapshot amounts, including the initial deposit + one maintenance period", () => {
    render(
      <OrderSummaryCard
        summary={{
          id: "o",
          revision: 2,
          packageName: "Professional",
          totalCents: 149500,
          depositCents: 29900,
          balanceCents: 119600,
          maintenanceMonthlyCents: 9900,
          scopeItems: ["Ten-page website"],
          businessLegalName: "Biz LLC",
        }}
      />,
    );
    const card = screen.getByRole("heading", { name: /Order summary/ }).parentElement!;
    expect(within(card).getByText("$398.00")).toBeTruthy();
    expect(within(card).getByText("$1,196.00")).toBeTruthy();
    expect(within(card).getByText("$99.00 per month")).toBeTruthy();
  });
});
