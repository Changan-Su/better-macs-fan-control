import { readFile, mkdir, writeFile } from "node:fs/promises";
const html = await readFile(
    new URL("../ui-demo/index.html", import.meta.url),
    "utf8",
);
const adapter = await readFile(
    new URL("../native-ui/adapter.js", import.meta.url),
    "utf8",
);
const css = await readFile(
    new URL("../native-ui/app.css", import.meta.url),
    "utf8",
);
if (!html.includes("/* NATIVE_ADAPTER */"))
    throw Error("Missing native adapter marker");
const output = html
    .replace("/* NATIVE_ADAPTER */", () => adapter)
    .replace("</style>", () => `${css}</style>`)
    .replace(
        "<head>",
        `<head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:">`,
    );
new Function(output.match(/<script>([\s\S]*?)<\/script>/)[1]);
await mkdir(new URL("../dist/native/", import.meta.url), { recursive: true });
await writeFile(new URL("../dist/native/index.html", import.meta.url), output);
console.log("Built shared native interface: dist/native/index.html");
