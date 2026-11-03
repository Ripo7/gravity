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

// Phase 2: on a touch screen, tapping Play on the main menu must start a level.
async function menuTap(useTouch) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 }, hasTouch: useTouch });
  const p = await ctx.newPage();
  let scene = "";
  let play = null;
  p.on("console", (m) => {
    const t = m.text();
    if (t.startsWith("SCENE")) scene = t;
    const mm = t.match(/^MENU_PLAY (\d+) (\d+)/);
    if (mm) play = [Number(mm[1]), Number(mm[2])];
  });
  await p.goto("http://localhost:8061/index.html");
  await p.waitForFunction(() => !document.getElementById("status"), null, { timeout: 120000 });
  for (let i = 0; i < 60 && !play; i++) await p.waitForTimeout(500);
  const box = await p.locator("canvas").boundingBox();
  const size = await p.evaluate(() => [document.querySelector("canvas").width, window.devicePixelRatio]);
  const [x, y] = play ?? [260, 330];
  // Godot reports canvas pixels; convert to CSS pixels.
  const sx = box.x + x * (box.width / size[0]);
  const sy = box.y + y * (box.width / size[0]);
  if (useTouch) await p.touchscreen.tap(sx, sy);
  else await p.mouse.click(sx, sy);
  for (let i = 0; i < 30 && !scene.startsWith("SCENE level"); i++) await p.waitForTimeout(500);
  console.log(`MENU ${useTouch ? "touch" : "mouse"} play=${play} at=${sx.toFixed(0)},${sy.toFixed(0)} -> ${scene}`);
  await ctx.close();
  return scene.startsWith("SCENE level");
}
const mouseOk = await menuTap(false);
const ok = await menuTap(true);
console.log(ok ? "TOUCH_MENU_OK" : `TOUCH_MENU_FAIL (mouse ${mouseOk ? "ok" : "also fails"})`);
await browser.close();
server.close();
if (!ok) process.exit(1);
