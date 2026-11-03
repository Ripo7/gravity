// Loads a web export, clicks into the game and holds movement keys,
// printing the player's position so CI can prove keyboard input works.
// Usage: node tools/web_input_probe.mjs build/web
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { chromium } from "playwright";

const root = process.argv[2] ?? "build/web";
const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm" };
const server = createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname)).replace(/^([/\\])+/, "");
  try {
    const body = await readFile(join(root, path || "index.html"));
    res.writeHead(200, { "Content-Type": types[extname(path)] ?? "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(8061, r));
const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
const lines = [];
page.on("console", (m) => {
  const t = m.text();
  if (/PROBE|ERROR|error/.test(t)) {
    lines.push(t);
    console.log(t);
  }
});
await page.goto("http://localhost:8061/index.html?mode=probe");
await page.waitForFunction(() => !document.getElementById("status"), null, { timeout: 120000 });
await page.waitForTimeout(3000);
await page.mouse.click(480, 270);
await page.waitForTimeout(1500);
for (const key of ["KeyW", "ArrowUp", "KeyD"]) {
  console.log(`HOLD ${key}`);
  await page.keyboard.down(key);
  await page.waitForTimeout(2500);
  await page.keyboard.up(key);
  await page.waitForTimeout(1000);
}
await browser.close();
server.close();
