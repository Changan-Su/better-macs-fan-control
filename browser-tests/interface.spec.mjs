import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.locator('.nav [data-page="settings"]').click();
    await page.locator("#setting-live").click();
    await page.locator('.nav [data-page="overview"]').click();
});

test("draft, application and undo are separate", async ({ page }) => {
    await page.locator('[data-mode="fixed"]').click();
    await page.locator("#rpm-number").fill("3000");
    await page.locator('.nav [data-page="sensors"]').click();
    await page.locator('.nav [data-page="control"]').click();
    await expect(page.locator("#rpm-number")).toHaveValue("3000");
    await expect(page.locator("#footer-control")).toHaveText("控制权：macOS");
    await page.locator("#apply-control").click();
    await page.locator('.nav [data-page="overview"]').click();
    await expect(page.locator(".fan-reading strong")).toHaveText([
        "3,000",
        "3,000",
    ]);
    await page.locator("#undo-action").click();
    await expect(page.locator("#footer-control")).toHaveText("控制权：macOS");
});
test("single fan scope and invalid inputs", async ({ page }) => {
    await page.locator('[data-edit-fan="0"]').click();
    await page.locator('[data-type="fixed"]').click();
    await page.locator("#rpm-number").fill("9000");
    await expect(page.locator("#apply-control")).toBeDisabled();
    await page.locator("#rpm-number").fill("3200");
    await page.locator("#apply-control").click();
    await page.locator('.nav [data-page="overview"]').click();
    await expect(page.locator(".fan-top .tag")).toHaveText([
        "固定转速",
        "系统自动",
    ]);
    await page.locator('[data-mode="sensor"]').click();
    await page.locator("#temp-start").fill("90");
    await page.locator("#temp-end").fill("80");
    await expect(page.locator("#apply-control")).toBeDisabled();
});
test("full blast uses actual per-fan maxima and is retained in editor", async ({
    page,
}) => {
    await page.locator('[data-mode="full"]').click();
    await expect(
        page.getByRole("dialog", { name: "将所有风扇调至全速？" }),
    ).toBeVisible();
    await page.locator('[data-dialog="full"]').click();
    await expect(page.locator(".fan-reading strong")).toHaveText([
        "5,800",
        "6,200",
    ]);
    await page.locator('.nav [data-page="control"]').click();
    await expect(page.locator('[data-type="full"]')).toHaveAttribute(
        "aria-pressed",
        "true",
    );
    await expect(page.locator("#apply-control")).toBeDisabled();
});
test("sensor search, favorites and units", async ({ page }) => {
    await page.locator('.nav [data-page="sensors"]').click();
    await page.locator("#sensor-search").fill("ssd");
    await expect(page.locator("#sensor-rows tr")).toHaveCount(1);
    await page.locator("#sensor-search").fill("");
    await page.locator('[data-star="battery"]').click();
    await page.locator('[data-star="ssd"]').click();
    await page.locator('#page-sensors [data-unit="f"]').click();
    await expect(page.locator("#legend-cpu")).toContainText("°F");
    await expect(page.locator("#key-temperatures")).toContainText("内置存储");
});
test("permission, fanless and unavailable states", async ({ page }) => {
    await page.locator("#scenario").selectOption("readonly");
    await expect(page.locator('[data-mode="fixed"]')).toBeDisabled();
    await page.locator('[data-action="authorize"]').click();
    await page.locator('[data-dialog="authorize"]').click();
    await expect(page.locator('[data-mode="fixed"]')).toBeEnabled();
    await page.locator("#scenario").selectOption("fanless");
    await expect(page.locator("#fanless-state")).toBeVisible();
    await expect(page.locator("#fans-section")).toBeHidden();
    await page.locator("#scenario").selectOption("sensorerror");
    await expect(page.locator("#legend-cpu")).toHaveText("—");
    await expect(page.locator("#footer-control")).toHaveText("控制权：macOS");
});
test("dialog focus and persisted preferences", async ({ page }) => {
    await page.locator(".toolbar-help").click();
    await expect(page.locator(".dialog")).toBeFocused();
    await page.keyboard.press("Escape");
    await expect(page.locator("#overlay")).toBeHidden();
    await page.locator('.nav [data-page="settings"]').click();
    await page.locator('[data-theme-choice="dark"]').click();
    await page.reload();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
});
for (const width of [1440, 1024, 768, 390, 320])
    test(`four pages fit ${width}px`, async ({ page }) => {
        await page.setViewportSize({ width, height: 1000 });
        for (const name of ["overview", "control", "sensors", "settings"]) {
            await page.locator(`.nav [data-page="${name}"]`).click();
            expect(
                await page.evaluate(() => document.documentElement.scrollWidth),
            ).toBeLessThanOrEqual(width);
        }
    });
