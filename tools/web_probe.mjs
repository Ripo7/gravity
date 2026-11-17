// Loads the web export in headless Chromium (software WebGL2), plays a short
// scripted run (three blows at the house) and checks that the house was
// built, that it broke, and that nothing failed on the way (a shader that
// does not compile in WebGL shows up here, not on desktop). Then loads a
// city, which has shaders of its own (its walls, its ground), and checks
// that it is built with nothing failing.
// Usage: node tools/web_probe.mjs build/web [screenshot.png]
//        (the city's picture goes next to it, as screenshot_city.png)
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

// Plays `query` on a new page until the run is over; the picture is taken
// `settle` ms after a line that starts with `shoot` has been printed.
// Returns what the game printed.
async function play(query, shoot, settle, picture) {
  const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
  const lines = [];
  page.on("console", (m) => {
    const t = m.text();
    lines.push(t);
    if (/BUILD|CITY|BLOW|PLAY_DONE|ERROR|error|shader/i.test(t)) console.log(t);
  });
  page.on("pageerror", (e) => console.log("PAGE ERROR " + e.message));
  await page.goto(`http://localhost:8061/index.html?${query}`, { timeout: 180000 });
  // Software WebGL is slow: a few seconds of game time can take a minute.
  let shot_taken = false;
  for (let i = 0; i < 600 && !lines.some((t) => t.startsWith("PLAY_DONE")); i++) {
    await page.waitForTimeout(500);
    if (picture && !shot_taken && lines.some((t) => t.startsWith(shoot))) {
      shot_taken = true;
      await page.waitForTimeout(settle);
      await page.screenshot({ path: picture });
    }
  }
  await page.close();
  const errors = lines.filter((t) => /SCRIPT ERROR|shader.*(error|fail)|ERROR:/i.test(t));
  if (errors.length) failures.push(`${errors.length} errors, first: ${errors[0]}`);
  return lines;
}

const steps = "a@-2.5,1.4,-0.6;w0.3;o;w0.8;o@-1.9,2.0,-0.6;w0.8;o@-1.5,1.4,2.7;w2.5";
const house = await play(
  `level=house&mode=play&from=-2.5,0.05,4.5&steps=${encodeURIComponent(steps)}`,
  "BLOW 3",
  4000,
  shot,
);
if (!house.some((t) => t.startsWith("BUILD"))) failures.push("the house was not built");
const done = house.find((t) => t.startsWith("PLAY_DONE"));
const m = done && done.match(/standing=(\d+)\/(\d+) pieces=(\d+)/);
if (!m) failures.push("the run did not finish");
else if (Number(m[1]) >= Number(m[2]) || Number(m[3]) < 5) failures.push("nothing broke");

const look = "a@6,0.5,-20;w1";
const city = await play(
  `mode=play&city=29&seed=1&from=6,0.05,12&steps=${encodeURIComponent(look)}`,
  "CITY",
  8000,
  shot && shot.replace(/\.png$/, "_city.png"),
);
if (!city.some((t) => t.startsWith("CITY"))) failures.push("the city was not built");
if (!city.some((t) => t.startsWith("PLAY_DONE"))) failures.push("the run in the city did not finish");

await browser.close();
server.close();
console.log(failures.length ? "WEB_FAIL " + failures.join("; ") : "WEB_OK");
process.exit(failures.length ? 1 : 0);
