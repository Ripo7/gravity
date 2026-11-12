// Loads the web export in headless Chromium (software WebGL2), plays a short
// scripted run (two shock waves at the house) and checks that the house was
// built, that it broke, and that nothing failed on the way (a shader that
// does not compile in WebGL shows up here, not on desktop).
// Usage: node tools/web_probe.mjs build/web [screenshot.png]
//        CHROME=/usr/bin/google-chrome to use an installed browser.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { chromium } from "playwright-core";

const root = process.argv[2] ?? "build/web";
const shot = process.argv[3];
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
const browser = await chromium.launch({
  executablePath: process.env.CHROME || undefined,
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
const lines = [];
page.on("console", (m) => {
  const t = m.text();
  lines.push(t);
  if (/BUILD|CAST|PLAY_DONE|ERROR|error|shader/i.test(t)) console.log(t);
});
page.on("pageerror", (e) => console.log("PAGE ERROR " + e.message));
const steps = "a@-2.5,1.4,-0.6;w0.3;o;w1.5;o@-1.5,1.4,2.7;w2.5";
await page.goto(`http://localhost:8061/index.html?mode=play&from=-2.5,0.05,4.5&steps=${encodeURIComponent(steps)}`);
// Software WebGL is slow: a few seconds of game time can take a minute.
let done;
for (let i = 0; i < 600 && !done; i++) {
  await page.waitForTimeout(500);
  if (shot && lines.some((t) => t.startsWith("CAST 2")) && !lines.shot) {
    lines.shot = true;
    await page.waitForTimeout(4000);
    await page.screenshot({ path: shot });
  }
  done = lines.find((t) => t.startsWith("PLAY_DONE"));
}
await browser.close();
server.close();

const failures = [];
const built = lines.find((t) => t.startsWith("BUILD"));
if (!built) failures.push("the house was not built");
const m = done && done.match(/standing=(\d+)\/(\d+) pieces=(\d+)/);
if (!m) failures.push("the run did not finish");
else if (Number(m[1]) >= Number(m[2]) || Number(m[3]) < 5) failures.push("nothing broke");
const errors = lines.filter((t) => /SCRIPT ERROR|shader.*(error|fail)|ERROR:/i.test(t));
if (errors.length) failures.push(`${errors.length} errors, first: ${errors[0]}`);
console.log(failures.length ? "WEB_FAIL " + failures.join("; ") : "WEB_OK");
process.exit(failures.length ? 1 : 0);
