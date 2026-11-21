// Loads the web export in headless Chromium (software WebGL2), plays a short
// scripted run on the bench (the brute runs, cuts the concrete column
// where its fists land on it, bends the metal post, dents a sheet twice,
// then brings down a post under the deck and snaps the wooden post)
// and checks that the bench
// was built, that the brute went where it was sent, that the column was
// cut, that the post and the sheet stand marked, that the deck came loose
// in its triangles, and that nothing failed on the way (a
// shader that does not compile in WebGL shows up here, not on desktop).
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
  if (/BENCH|WALKED|PROF|PLAY_DONE|ERROR|error|shader/i.test(t)) console.log(t);
});
page.on("pageerror", (e) => console.log("PAGE ERROR " + e.message));
// Run forward a second, then stand a step from the concrete column and
// keep striking for three combinations (it is cut at the seventh blow);
// one combination and a blow at the metal post; two blows at a sheet of
// the fence; three combinations at a post under the deck (it lies down
// at the sixth blow); one blow at the wooden post (it is cut there).
const mash = (seconds) => Array(Math.round(seconds / 0.25)).fill("h;w0.25").join(";");
const steps =
  `f1;w0.3;s1.5,0.05,-5.0,1.5,1,-6;${mash(6.5)};w4;s-1.5,0.05,-5.0,-1.5,1,-6;${mash(2.2)};w2;` +
  `s-4.5,0.05,-7.0,-4.5,1,-8;w0.3;h;w0.4;h;w1.5;` +
  `s-7.4,0.05,-4.9,-7.4,1,-5.9;${mash(6)};w3;` +
  `s0,0.05,-9.1,0,1,-10;w0.3;h;w2.5;` +
  // One blow at a pane of glass, behind where it started: it bursts
  // (its glitter is drawn by a shader of its own).
  `s0,0.05,7.1,0,1,8;w0.3;h;w2.5;` +
  // A combination at the middle of a gable of the house, which stands
  // 30 degrees askew: it cuts the post
  // under the ridge, and the roof (the ridge, its rafters and its boards,
  // which are tilted: seventeen pieces) comes down.
  `s5.65,0.05,4.34,7,1,2;w0.3;${mash(2)};w3.5;` +
  // The three columns of the front of the office building, one after the
  // other (each is cut at the fourth blow): the first slab comes down
  // with the two storeys and the roof on it, fifty-nine pieces in all,
  // and breaks.
  `s-5.74,0.05,3.46,-6.30,1,3.66;w0.3;${mash(3.5)};w1;` +
  `s-6.31,0.05,1.88,-6.87,1,2.09;w0.3;${mash(3.5)};w1;` +
  `s-6.88,0.05,0.31,-7.45,1,0.52;w0.3;${mash(3.5)};w5;` +
  // A post at a corner of the foot of the tower, which stands behind the
  // start, 15 degrees askew (it gives at the sixth straight that lands on
  // it, and bowed, it is no longer where some of them land: four
  // combinations): the four decks and the twelve posts over it come
  // loose in one, the twelve panes over it burst, and the frame lies
  // down.
  `s1.56,0.05,19.97,1.38,1,19.30;w0.3;${mash(8)};w7`;
// Software WebGL is slow: loading alone can take a while.
await page.goto(`http://localhost:8061/index.html?mode=play&prof&steps=${encodeURIComponent(steps)}`, { timeout: 180000 });
// And a few seconds of game time can take a minute.
let done;
for (let i = 0; i < 1000 && !done; i++) {
  await page.waitForTimeout(500);
  // Once blocks lie loose: a picture of them.
  if (shot && lines.some((t) => /^PROF.*loose [1-9]/.test(t)) && !lines.shot) {
    lines.shot = true;
    await page.waitForTimeout(3000);
    await page.screenshot({ path: shot });
  }
  done = lines.find((t) => t.startsWith("PLAY_DONE"));
}
await browser.close();
server.close();

const failures = [];
if (!lines.some((t) => /^BENCH ready: [1-9]\d* pieces/.test(t))) failures.push("the bench was not built");
// "WALKED to (x, y, z) (on floor: true)": forward is -z.
const walked = lines.find((t) => t.startsWith("WALKED"));
const m = walked && walked.match(/\(([-\d.]+), ([-\d.]+), ([-\d.]+)\) \(on floor: (\w+)\)/);
if (!done) failures.push("the run did not finish");
else if (!m) failures.push("the brute did not report where it went");
else if (Number(m[3]) > -2 || m[4] !== "true") failures.push(`the brute did not run forward on the ground: ${walked}`);
// "PLAY_DONE at=... standing=39/41 marked=4 loose=18 ...": the column is
// cut where the fists landed (its foot stands, the rest is down, in blocks);
// the post and the sheet stand, marked; a post under the deck has lain
// down in its two limbs, and the deck has come loose in its eight
// triangles.
const end = done && done.match(/standing=(\d+)\/(\d+) marked=(\d+) loose=(\d+)/);
if (done && (!end || Number(end[1]) >= Number(end[2]) || Number(end[4]) < 2)) failures.push(`nothing came down: ${done}`);
if (end && Number(end[3]) < 4) failures.push(`the column, the two posts and the sheet were not all marked: ${done}`);
if (end && (Number(end[1]) > Number(end[2]) - 3 || Number(end[4]) < 14)) failures.push(`the column or the wooden post was not cut, the deck did not come loose, or the pane did not burst: ${done}`);
if (end && Number(end[1]) > Number(end[2]) - 20) failures.push(`the roof of the house did not come down: ${done}`);
if (end && Number(end[1]) > Number(end[2]) - 70) failures.push(`the office building did not come down: ${done}`);
if (end && Number(end[1]) > Number(end[2]) - 70 - 29) failures.push(`the tower did not come down: ${done}`);
const errors = lines.filter((t) => /SCRIPT ERROR|shader.*(error|fail)|ERROR:/i.test(t));
if (errors.length) failures.push(`${errors.length} errors, first: ${errors[0]}`);
console.log(failures.length ? "WEB_FAIL " + failures.join("; ") : "WEB_OK");
process.exit(failures.length ? 1 : 0);
