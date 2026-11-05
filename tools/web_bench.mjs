// Serves a web export and runs the in-game benchmark in headless Chromium.
// Usage: node tools/web_bench.mjs build/web [max-bodies]
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { chromium } from "playwright";

const root = process.argv[2] ?? "build/web";
const max = process.argv[3] ?? "1500";
const types = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
};

const server = createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname)).replace(/^([/\\])+/, "");
  try {
    const body = await readFile(join(root, path || "index.html"));
    res.writeHead(200, {
      "Content-Type": types[extname(path)] ?? "application/octet-stream",
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    });
    res.end(body);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(8060, r));

const browser = await chromium.launch({
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
let done;
const finished = new Promise((r) => (done = r));
page.on("console", (msg) => {
  const text = msg.text();
  if (/BENCH|ERROR|SCRIPT ERROR/.test(text)) console.log(text);
  if (text.includes("BENCH_DONE")) done();
});
await page.goto(`http://localhost:8060/index.html?mode=bench&max=${max}`);
const timeout = setTimeout(() => {
  console.log("BENCH_TIMEOUT");
  done();
}, 12 * 60 * 1000);
await finished;
clearTimeout(timeout);
await browser.close();
server.close();
