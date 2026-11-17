import http from "node:http";
import { readFile } from "node:fs/promises";
import { resolve, sep } from "node:path";
const port = Number(process.env.PORT || 5178);
const root = resolve("ui-demo"),
    native = resolve("dist/native");
http.createServer(async (req, res) => {
    try {
        const pathname = decodeURIComponent(
            new URL(req.url, "http://localhost").pathname,
        );
        if (pathname === "/favicon.ico") {
            res.writeHead(204);
            res.end();
            return;
        }
        const isNative = pathname.startsWith("/native/");
        const base = isNative ? native : root;
        const relative = isNative
            ? pathname.slice("/native/".length)
            : pathname.slice(1);
        const target = resolve(
            base,
            relative.endsWith("/") || !relative
                ? relative + "index.html"
                : relative,
        );
        if (!target.startsWith(base + sep)) {
            res.writeHead(403);
            res.end();
            return;
        }
        const data = await readFile(target);
        res.writeHead(200, {
            "content-type": target.endsWith(".html")
                ? "text/html; charset=utf-8"
                : target.endsWith(".png")
                  ? "image/png"
                  : "application/octet-stream",
            "cache-control": "no-store",
        });
        res.end(data);
    } catch {
        res.writeHead(404);
        res.end("Not found");
    }
}).listen(port, "127.0.0.1", () =>
    console.log(`Better Fan preview: http://127.0.0.1:${port}`),
);
