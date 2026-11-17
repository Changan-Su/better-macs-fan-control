import { defineConfig, devices } from "@playwright/test";
export default defineConfig({
    testDir: "./browser-tests",
    fullyParallel: true,
    forbidOnly: !!process.env.CI,
    retries: process.env.CI ? 1 : 0,
    workers: process.env.CI ? 2 : undefined,
    globalTimeout: 240000,
    timeout: 30000,
    reporter: [["list"], ["html", { open: "never" }]],
    use: {
        baseURL: "http://127.0.0.1:5178",
        trace: "retain-on-failure",
        screenshot: "only-on-failure",
    },
    projects: [
        { name: "chromium", use: { ...devices["Desktop Chrome"] } },
        { name: "webkit", use: { ...devices["Desktop Safari"] } },
    ],
    webServer: {
        command: "node scripts/build-ui.mjs && node scripts/serve.mjs",
        url: "http://127.0.0.1:5178",
        reuseExistingServer: !process.env.CI,
    },
});
