"""AutoCAD integration test: runs cable_tray_router.lsp in accoreconsole on a
SCRATCH copy of a drawing, saves DXF after stage 1 and stage 2, and checks the
generated geometry with ezdxf.  Reuses dwg_batch_tool's verified run_accore /
decode_console helpers and its SAVEAS DXF script pattern.
Usage: <venv python> tools/acc_integration.py <scratch_dir>
"""
import math, os, shutil, sys
from collections import Counter
from pathlib import Path

PROJ = Path(r"D:\github\ezdxf\dwg_batch_tool\scripts")
sys.path.insert(0, str(PROJ))
from common import decode_console          # noqa: E402
from convert_single import run_accore      # noqa: E402
import ezdxf                               # noqa: E402

ACC = r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe"
work = Path(sys.argv[1]); work.mkdir(parents=True, exist_ok=True)
base = work / "base.dwg"
shutil.copy(r"D:\github\ezdxf\dwg_batch_tool\tests\fixtures\sample.dwg", base)
s1, s2 = work / "stage1.dxf", work / "stage2.dxf"
for f in (s1, s2): f.unlink(missing_ok=True)
fw = lambda p: str(p).replace("\\", "/")
scr = work / "it.scr"

# SECURELOAD=1 + empty TRUSTEDPATHS blocks (load) from D:/BLOCK.  We do NOT change
# security settings; instead feed the comment-stripped source through the script.
sys.path.insert(0, str(Path(__file__).parent))
from lisp_sim import TOKEN


def inline(path):
    src = Path(path).read_text(encoding="utf-8")
    parts = []
    for m in TOKEN.finditer(src):
        t = m.group(0)
        if t.startswith(";"):
            continue
        parts.append(t)
    lines = [l.rstrip() for l in "".join(parts).splitlines() if l.strip()]
    return chr(10).join(l for l in lines if not l.lstrip().startswith("(load "))


from ctr_paths import rp  # BLOCK router dir; CTR_BLOCK_ROUTER_DIR overrides D:/BLOCK/router
inline_src = (inline(rp("cable_tray_router.lsp")) + chr(10)
              + inline(rp("tools/it_scenario.lsp")))
LF = chr(10)
script = LF.join(["FILEDIA", "0", inline_src, "(it-stage1)", "_SAVEAS", "DXF", "", fw(s1),
                  "(it-stage2-undo)", "(it-stage2)", "_SAVEAS", "DXF", "", fw(s2), "_QUIT", ""])
scr.write_bytes(script.encode("mbcs"))
rc, out, err, why = run_accore([ACC, "/i", str(base), "/s", str(scr), "/l", "en-US"], 240)
log = decode_console(out)
(work / "it.stdout.log").write_text(log, encoding="utf-8")
print("rc", rc, "why", why or "-", "| stage1", s1.exists(), "stage2", s2.exists())
for line in log.splitlines():
    if "[CTR]" in line or "IT_COUNT" in line or "rror" in line or "\u932f" in line:
        print("  LOG:", line.strip()[:200])

def summarize(path, tag):
    d = ezdxf.readfile(path); m = d.modelspace()
    tray = [e for e in m if e.dxf.layer == "SCADA-TRAY"]
    c = Counter()
    ins = []
    for e in tray:
        if e.dxftype() == "INSERT":
            c[e.dxf.name] += 1
            ins.append((e.dxf.name, round(e.dxf.insert.x, 1), round(e.dxf.insert.y, 1),
                        round(e.dxf.rotation, 1), round(e.dxf.xscale, 4)))
        else:
            c[e.dxftype()] += 1
    path_ents = [e for e in m if e.dxf.layer == "SCADA-TRAY-PATH"]
    print(f"== {tag}: tray objs {len(tray)} {dict(c)} | path objs {len(path_ents)}")
    return d, tray, ins

def rect_of(e):
    pts = [(round(p[0], 1), round(p[1], 1)) for p in e.get_points()]
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)

if s1.exists():
    d, tray, ins = summarize(s1, "stage1")
    for i in sorted(ins, key=lambda t: (t[2], t[1])): print("   INSERT", i)
    print("   straights (bbox x0,y0,x1,y1):")
    for e in tray:
        if e.dxftype() == "LWPOLYLINE":
            b = rect_of(e)
            if b[1] < 5000: print("     P1", b)
if s2.exists():
    d, tray, ins = summarize(s2, "stage2")
    near = [i for i in ins if i[2] < 1000]
    print("   stage2 fittings in Phase-1 area:", near)
