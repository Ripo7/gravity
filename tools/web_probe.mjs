// Loads the web export in headless Chromium (software WebGL2), plays a short
// scripted run on the bench (the brute runs, strikes and kicks) and checks
// that the bench was built, that the brute went where it was sent, and that
// nothing failed on the way (a shader that does not compile in WebGL shows
// up here, not on desktop).
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
  if (/BENCH|WALKED|PLAY_DONE|ERROR|error|shader/i.test(t)) console.log(t);
});
page.on("pageerror", (e) => console.log("PAGE ERROR " + e.message));
// Run forward a second, a blow, a kick.
const steps = "f1;w0.3;h;w1.2;k;w1.5";
// Software WebGL is slow: loading alone can take a while.
await page.goto(`http://localhost:8061/index.html?mode=play&steps=${encodeURIComponent(steps)}`, { timeout: 180000 });
// And a few seconds of game time can take a minute.
let done;
for (let i = 0; i < 600 && !done; i++) {
  await page.waitForTimeout(500);
  if (shot && lines.some((t) => t.startsWith("WALKED")) && !lines.shot) {
    lines.shot = true;
    await page.waitForTimeout(2000);
    await page.screenshot({ path: shot });
  }
  done = lines.find((t) => t.startsWith("PLAY_DONE"));
}
await browser.close();
server.close();

const failures = [];
if (!lines.some((t) => t.startsWith("BENCH ready"))) failures.push("the bench was not built");
// "WALKED to (x, y, z) (on floor: true)": forward is -z.
const walked = lines.find((t) => t.startsWith("WALKED"));
const m = walked && walked.match(/\(([-\d.]+), ([-\d.]+), ([-\d.]+)\) \(on floor: (\w+)\)/);
if (!done) failures.push("the run did not finish");
else if (!m) failures.push("the brute did not report where it went");
else if (Number(m[3]) > -2 || m[4] !== "true") failures.push(`the brute did not run forward on the ground: ${walked}`);
const errors = lines.filter((t) => /SCRIPT ERROR|shader.*(error|fail)|ERROR:/i.test(t));
if (errors.length) failures.push(`${errors.length} errors, first: ${errors[0]}`);
console.log(failures.length ? "WEB_FAIL " + failures.join("; ") : "WEB_OK");
process.exit(failures.length ? 1 : 0);
