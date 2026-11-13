// Loads the web export in headless Chromium (software WebGL2) and plays two
// short scripted runs: in the house (two shock waves, then the orb held open
// on the debris) and in the course (a shock wave at its first wall). Checks
// that each was built, that it broke, that the orb swallowed something, and
// that nothing failed on the way (a shader that does not compile in WebGL
// shows up here, not on desktop). Screenshots: the house while the orb is
// open, the course after the shock wave (same name, ending in -course).
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
const failures = [];

// Plays `query` (what follows index.html?) to its end. The screenshot is
// taken `wait` ms after a line starting with `after` is printed.
async function run(query, shot, after, wait) {
  const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
  const lines = [];
  page.on("console", (m) => {
    const t = m.text();
    lines.push(t);
    if (/BUILD|CAST|GATHER|ORB|PLAY_DONE|ERROR|error|shader/i.test(t)) console.log(t);
  });
  page.on("pageerror", (e) => console.log("PAGE ERROR " + e.message));
  await page.goto(`http://localhost:8061/index.html?${query}`);
  // Software WebGL is slow: a few seconds of game time can take a minute.
  let done;
  let taken = false;
  for (let i = 0; i < 600 && !done; i++) {
    await page.waitForTimeout(500);
    if (shot && !taken && lines.some((t) => t.startsWith(after))) {
      taken = true;
      await page.waitForTimeout(wait);
      await page.screenshot({ path: shot });
    }
    done = lines.find((t) => t.startsWith("PLAY_DONE"));
  }
  await page.close();
  const m = done && done.match(/standing=(\d+)\/(\d+) pieces=(\d+)/);
  if (!m) failures.push(`${query.split("&")[0]}: the run did not finish`);
  else if (Number(m[1]) >= Number(m[2]) || Number(m[3]) < 5) failures.push(`${query.split("&")[0]}: nothing broke`);
  const errors = lines.filter((t) => /SCRIPT ERROR|shader.*(error|fail)|ERROR:/i.test(t));
  if (errors.length) failures.push(`${errors.length} errors, first: ${errors[0]}`);
  return lines;
}

const steps = "a@-2.5,1.4,-0.6;w0.3;o;w1.5;o@-1.5,1.4,2.7;w2.5;g;w2.5;t;w1.5";
const house = await run(
  `level=house&mode=play&from=-2.5,0.05,4.5&steps=${encodeURIComponent(steps)}`,
  shot,
  "GATHER",
  9000,
);
if (!house.some((t) => t.startsWith("BUILD house"))) failures.push("the house was not built");
const orb = house.find((t) => t.startsWith("ORB"));
if (!orb || !(parseFloat(orb.split(" ")[1]) > 0)) failures.push("the orb swallowed nothing");

// The course: its first wall, from where you start.
const course = await run(
  `level=course&mode=play&steps=${encodeURIComponent("f0.7;o@0,1.2,-2;w2")}`,
  shot && shot.replace(/(\.\w+)?$/, "-course$1"),
  "CAST",
  6000,
);
if (!course.some((t) => t.startsWith("BUILD course"))) failures.push("the course was not built");

await browser.close();
server.close();
console.log(failures.length ? "WEB_FAIL " + failures.join("; ") : "WEB_OK");
process.exit(failures.length ? 1 : 0);
