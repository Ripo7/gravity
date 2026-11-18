# Gravity: a giant brute, and what it breaks

A giant brute in a toy city that breaks, seen in third person. The game
is being rebuilt from its concept, one step at a time, in greybox:
[docs/CONCEPT.md](docs/CONCEPT.md) (in French) says what it is to be, and
comes before the code.

**Where it is now: step 3 of 7, metal.** A bare ground, one brute that
walks, runs, sprints, jumps, throws a four-blow combination and kicks, and
on the bench in front of it the same three things twice: a column, a
wall, a slab on four columns. In concrete on its right, in metal on its
left.

A blow harms the place it lands on, not the whole piece. Concrete cracks
round the blow, for all to see, then lets go there: the few big blocks
round the fist are knocked out, away from the blow, and a wall keeps a
hole. What they held up comes down, breaks into its blocks when it lands
and lies low; the rest stands.
Metal never breaks: a blow leaves its mark where it lands, away from
the blow, and the piece keeps it. A sheet takes a dent under the fist, a
post kinks at the height it is struck at. Marked as deep as it goes in
one place, it lies down; a post that gives under a load folds, and a
plate sags where nothing holds it any more. What a piece carried comes
down when the piece is gone. Walking breaks nothing.

What breaks is worked out one material at a time, each on this bench and
each tried on a phone before the next: concrete, then metal, wood, glass;
then a house, an office and a tower made of them; then the city, made up
from a number as before.

Godot 4.7, GDScript, Jolt physics, Compatibility renderer (WebGL2), so it
can be played in Safari on an iPhone from each pull request's preview.

The version before this one (two brutes fighting in a city of boxes cut
into shards) is kept as it was on the branch
[`archive/v1`](../../tree/archive/v1); what it taught is at the end of
the concept. The project before that is on
[`archive/gravity`](../../tree/archive/gravity).

## Controls

| | Keyboard and mouse | Phone |
| --- | --- | --- |
| Move | WASD (by position, so ZQSD on AZERTY) / arrows | left stick: pushed a little, a walk; fully, a run |
| Sprint | shift | the stick held fully pushed for 0.8 s |
| Look | mouse | drag on the right half |
| Strike | left click or F | big red button |
| Kick | right click or E | orange button |
| Jump | space | small button |
| Put the bench back | R | "Reconstruire" |
| How fast things fall | the slider at the top | the slider at the top |

The camera sits behind the character's left shoulder and turns about its
head; it comes closer when a wall is behind (and the character is not
drawn when the camera is right against its back). The character goes where
you push, seen from the camera, and turns to face where it goes.

The strike button throws a lunging hook; pressed again before it is over,
the next blow of the combination follows: a swing up from the right, one
back across from the left, then a leap that comes down fist first, then
round again. A blow is thrown where the stick pushes, or where the
character faces.

A place of a concrete piece 0.4 m thick takes one whole combination:
three blows crack it, wider each time, and the fourth, the heavy one,
knocks out the blocks round it. A column is cut there: its foot stays,
its top comes down. A wall keeps a hole about 0.9 m across where the
fist landed; another one or two beside it, and what was over them comes
down: the way is open.
A metal post 0.2 m thick takes a combination and a half where the fists
land: it leans more at each blow and lies down at the seventh. A sheet
takes a dent at each blow and lies down at the third in the same place;
blows elsewhere start other dents. A blow from the other side takes as
much back. A kick is as heavy as the fourth blow of the combination.

The slider ("Chute") sets how fast what has come off falls, as a share of
real gravity: 1 to begin with, as things really fall (what the owner
settled on, on the phone); less, and they fall slowly, which was tried
to make the brute a giant.

The line at the top left shows frames per second, the cost of one physics
step, how many pieces still stand, how many loose bodies there are (and
how many are moving) and which build this is (it ends with the commit).

## Run

```sh
godot --path .                                                # play
godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn   # tests
godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn -- --only=concrete
pip install "gdtoolkit==4.5.0" && gdlint scripts tests && gdformat --check scripts tests
```

`tools/install_godot.sh` downloads the right Godot (and `--templates` the
export templates) into `~/.godot-ci`.

Scripted runs (`scripts/core/director.gd`), on desktop after `--`, in a
browser as `index.html?mode=...`:

```sh
# Stand in front of the concrete column and throw the four blows at it.
godot --path . -- --mode=play --steps="s1.5,0.05,-4.55,1.5,1,-6;w0.3;h;w0.4;h;w0.4;h;w0.4;h;w5"
# The same at the metal post, without a screen, with the cost of the physics.
godot --headless --fixed-fps 60 --path . -- --mode=play --prof --steps="s-1.5,0.05,-4.6,-1.5,1,-6;w0.3;h;w0.4;h;w0.4;h;w0.4;h;w5"
# Just look, from somewhere at something.
godot --path . -- --mode=still --pos=0,0.05,4 --at=0,1,-8 --wait=2
# What the picture costs here while the bench is broken (see docs/PERFORMANCE.md).
godot --path . -- --mode=mesure
```

Add `--write-movie out.avi --fixed-fps 30` before `--path` to record a run.

## Checks

- `tests/`: a small headless runner; files `tests/test_*.gd`, methods
  `test_*` (they may `await`). They play the real scene: the bench (one
  brute, what stands on it, no sun shadow, a round shadow that stays on
  the ground, putting it all back); concrete (walking, running and
  jumping break nothing; a column cracks where it is struck, then is cut
  there; struck half way up, its foot stays and its top comes down in one
  and breaks when it lands; a wall struck in the middle keeps a hole;
  over the hole of one blow the wall holds, over a wider one it comes
  down; a piece, and a place of it, take what its matter and its
  size say however it is cut; a slab holds on three columns and comes
  down without two; what lands on a piece is a blow to it; things fall
  as fast as they are set to; the brute knocks a hole in the wall,
  round its fist, then a way through); metal (walking
  bends nothing; a post bends blow after blow, keeps the shape and never
  breaks; a blow from the other side straightens it; it kinks at each
  height it is struck at; a post that carries bows and keeps its head
  under what it carries; a post that gives under a deck folds, and the
  deck sags there, still on the posts that stand; metal that comes down
  from high lands whole; what lands on metal bends it; a sheet takes a
  dent under the fist and the rest stays flat; dented deep enough in one
  place it lies down and opens the fence; the brute does not hold up
  what comes down on it, and does not throw what it walks into); the
  character
  (where the camera sits and how it comes in at a wall, the character
  turning to where it goes, its planted foot not sliding from a slow walk
  to a sprint, jumps and landings, stepping onto what is low); the blows
  (the four in order then standing again, each one saying when it lands,
  how far and how hard, the kick); the controls, keys and thumbs; and the
  cut of a box into blocks (volumes, shared faces).
- `tools/web_probe.mjs`: loads the web export in headless Chromium, has
  the brute break the concrete column and bend the metal post, and fails
  on any error (`npm install playwright`, then
  `node tools/web_probe.mjs build/web shot.png`). WebGL2 is stricter than
  desktop OpenGL: two bugs only showed there.
- `.github/workflows/ci.yml` runs lint, tests, the web export and the
  probe on every pull request. Vercel builds a preview of the web export
  for every push (`vercel.json`, `tools/vercel_build.sh`).

## More

- [docs/CONCEPT.md](docs/CONCEPT.md): what the game is to be, and the plan.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the code is laid out.
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md): what was measured, and how.
- [CONTRIBUTING.md](CONTRIBUTING.md): the way a change goes in.
- [CREDITS.md](CREDITS.md): where the assets come from and their terms.
