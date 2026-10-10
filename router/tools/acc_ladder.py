"""GENERATED_LADDER integration test: real AutoCAD engine, straights at
1000/2000/3000 (horizontal, width 750), one vertical (width 300) and 1100/1150/1250.
Usage: <venv python> acc_ladder.py <scratch_dir>      exit code = number of failed assertions

The geometry of every generated rail and rung is ASSERTED against expectations written down HERE, not
read back from the router's config, so a wrong production constant cannot silently validate itself:
  OWNER_MAX_RUNG_SPACING = 225   Owner Requirements (2), clause 1.15.2(1)A.c: rung centre-to-centre MAX
  PREFERRED_RUNG_SPACING = 225   the value the router is meant to render
  FIRST_RUNG_OFFSET      = 125   measured from the real block (unchanged)
  RUNG_WIDTH 40 / RAIL_THICKNESS 20 / rail centre-line offset = width/2   (block_spec_measured.md)
Rung count rule: floor(length / spacing), rungs never beyond the segment.
"""
import sys
from pathlib import Path
sys.path.insert(0, r"D:\github\ezdxf\dwg_batch_tool\scripts")
sys.path.insert(0, str(Path(__file__).parent))
from common import decode_console
from convert_single import run_accore
from lisp_sim import TOKEN
import shutil

work = Path(sys.argv[1]); work.mkdir(parents=True, exist_ok=True)
base = work / "base.dwg"
shutil.copy(r"D:\github\ezdxf\dwg_batch_tool\tests\fixtures\sample.dwg", base)


def inline(path):
    src = Path(path).read_text(encoding="utf-8")
    parts = [m.group(0) for m in TOKEN.finditer(src) if not m.group(0).startswith(";")]
    lines = [l.rstrip() for l in "".join(parts).splitlines() if l.strip()]
    return chr(10).join(l for l in lines if not l.lstrip().startswith("(load "))


from ctr_paths import rp  # BLOCK router dir; CTR_BLOCK_ROUTER_DIR overrides D:/BLOCK/router
inline_src = (inline(rp("cable_tray_router.lsp")) + chr(10)
              + inline(rp("tools/it_scenario.lsp")) + chr(10)
              + inline(rp("tools/it_ladder.lsp")))
LF = chr(10)
scr = work / "l.scr"
scr.write_bytes((LF.join(["FILEDIA", "0", inline_src, "(it-ladder-h)", "(it-dump-polys)",
                          "_QUIT", "Y", ""])).encode("mbcs"))
rc, out, err, why = run_accore([r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe",
                                 "/i", str(base), "/s", str(scr), "/l", "en-US"], 240)
log = decode_console(out)
(work / "l.stdout.log").write_text(log, encoding="utf-8")
print("rc", rc, why or "-")
for line in log.splitlines():
    if any(k in line for k in ("[CTR]", "LADDER_CHECK", "POLY ")) and "(defun" not in line and "princ" not in line:
        print("  ", line.strip()[:200])

# ---- assertions (the dump above is what AutoCAD actually created) ---------------------------------------------
import math
import re

OWNER_MAX_RUNG_SPACING = 225.0
PREFERRED_RUNG_SPACING = 225.0
FIRST_RUNG_OFFSET = 125.0
RUNG_WIDTH = 40.0
RAIL_THICKNESS = 20.0
TOL = 0.05

POLY = re.compile(r"^POLY\s+(-?[\d.]+),(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)\s*$")
polys = []
for line in log.splitlines():
    m = POLY.match(line.strip())
    if m:
        polys.append(tuple(float(g) for g in m.groups()))

# (name, start x, start y, length, width, axis)   axis "h": along +X, "v": along +Y
SCENARIOS = [
    ("h1000", 0.0, 0.0, 1000.0, 750.0, "h"),
    ("h2000", 0.0, 5000.0, 2000.0, 750.0, "h"),
    ("h3000", 0.0, 10000.0, 3000.0, 750.0, "h"),
    ("v1000_w300", 20000.0, 0.0, 1000.0, 300.0, "v"),
    ("h1100", 0.0, 20000.0, 1100.0, 750.0, "h"),
    ("h1150", 0.0, 25000.0, 1150.0, 750.0, "h"),
    ("h1250", 0.0, 30000.0, 1250.0, 750.0, "h"),
]

failures = 0


def check(name, ok, detail=""):
    global failures
    failures += (not ok)
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", name, ("   " + detail) if (detail and not ok) else ""))
    return ok


def near(a, b, tol=TOL):
    return abs(a - b) <= tol


total_expected = 0
for name, x0, y0, length, width, axis in SCENARIOS:
    # normalise to (along-min, across-min, along-max, across-max) relative to the segment start
    if axis == "h":
        box = [(p[0] - x0, p[1] - y0, p[2] - x0, p[3] - y0) for p in polys]
    else:
        box = [(p[1] - y0, p[0] - x0, p[3] - y0, p[2] - x0) for p in polys]
    half = width / 2.0
    mine = [b for b in box if -1.0 <= b[0] and b[2] <= length + 1.0 and abs((b[1] + b[3]) / 2.0) <= half + 1.0]
    rails = [b for b in mine if near(b[0], 0.0) and near(b[2], length)]
    rungs = [b for b in mine if near(b[2] - b[0], RUNG_WIDTH)]
    exp_n = int(math.floor(length / PREFERRED_RUNG_SPACING + 1e-9))
    exp_centres = [FIRST_RUNG_OFFSET + PREFERRED_RUNG_SPACING * k for k in range(exp_n)]
    total_expected += 2 + exp_n

    # rails: two, full length, thickness 20, centre-lines at +-width/2
    rail_c = sorted(round((r[1] + r[3]) / 2.0, 3) for r in rails)
    check("%s: 2 rails over the full %g length, thickness %g, centre-line +-%g"
          % (name, length, RAIL_THICKNESS, half),
          len(rails) == 2 and all(near(r[3] - r[1], RAIL_THICKNESS) for r in rails)
          and len(rail_c) == 2 and near(rail_c[0], -half) and near(rail_c[1], half),
          "rails=%s" % rails)
    # rungs: count + exact centres
    centres = sorted((r[0] + r[2]) / 2.0 for r in rungs)
    check("%s: %d rungs (floor(%g/%g))" % (name, exp_n, length, PREFERRED_RUNG_SPACING), len(rungs) == exp_n,
          "got %d" % len(rungs))
    check("%s: rung centres == %s" % (name, exp_centres if exp_n <= 5 else "125 + 225*k, k=0..%d" % (exp_n - 1)),
          len(centres) == exp_n and all(near(a, b) for a, b in zip(centres, exp_centres)), "got %s" % centres)
    # owner maximum, independent of the preferred value
    gaps = [b - a for a, b in zip(centres, centres[1:])]
    check("%s: every rung centre-to-centre gap <= owner max %g" % (name, OWNER_MAX_RUNG_SPACING),
          all(g <= OWNER_MAX_RUNG_SPACING + TOL for g in gaps), "gaps=%s" % gaps)
    # rungs: span between the rails' inner faces, never past either end of the segment
    check("%s: rungs span +-(width/2-%g) and stay inside 0..%g" % (name, RAIL_THICKNESS, length),
          all(near(r[1], -(half - RAIL_THICKNESS)) and near(r[3], half - RAIL_THICKNESS) for r in rungs)
          and all(r[0] >= -TOL and r[2] <= length + TOL for r in rungs))

# the 1000 mm segment, spelled out literally (the figure the owner-rule fix is about)
r1000 = sorted(round(((p[0] + p[2]) / 2.0), 3) for p in polys
               if near(p[2] - p[0], RUNG_WIDTH) and -400.0 < p[1] < -300.0 and p[2] <= 1001.0)
check("h1000 literal rung centres are exactly [125, 350, 575, 800] (225 mm, not 250's 125/375/625/875)",
      r1000 == [125.0, 350.0, 575.0, 800.0], "got %s" % r1000)
check("5th rung boundary: 1100 -> 4 rungs, 1150 -> 5 rungs (floor(L/225)); 1250 -> 5 rungs",
      sum(1 for p in polys if near(p[2] - p[0], RUNG_WIDTH) and 24000 < p[1] < 25400 and p[2] < 1200) == 5
      and sum(1 for p in polys if near(p[2] - p[0], RUNG_WIDTH) and 19000 < p[1] < 20400 and p[2] < 1200) == 4
      and sum(1 for p in polys if near(p[2] - p[0], RUNG_WIDTH) and 29000 < p[1] < 30400 and p[2] < 1300) == 5)

check("no stray SCADA-TRAY polylines: dumped %d == expected %d" % (len(polys), total_expected),
      len(polys) == total_expected)
check("console reported no [CTR][ERROR]", "[CTR][ERROR]" not in log)
print("  assertions failed:", failures)
sys.exit(failures)
