"""Full end-to-end CTRAY test WITH a turn (Straight+Elbow+Straight), typed
exactly as the GUI would: profile keyword, width, 3 points, Enter. This is
the scenario the user's screenshot showed failing (elbow renders, straight
doesn't get rungs) -- unlike acc_ctray_e2e.py's single isolated straight.
Usage: <venv python> acc_ctray_e2e2.py <scratch_dir>
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
out = work / "ctray_e2e2.dxf"
out.unlink(missing_ok=True)


def inline(path):
    src = Path(path).read_text(encoding="utf-8")
    parts = [m.group(0) for m in TOKEN.finditer(src) if not m.group(0).startswith(";")]
    lines = [l.rstrip() for l in "".join(parts).splitlines() if l.strip()]
    return chr(10).join(l for l in lines if not l.lstrip().startswith("(load "))


LF = chr(10)
from ctr_paths import rp  # BLOCK router dir; CTR_BLOCK_ROUTER_DIR overrides D:/BLOCK/router
L = ["FILEDIA", "0", inline(rp("cable_tray_router.lsp"))]
L += ['(princ (strcat "' + '\\n' + 'OBJ_BEFORE=" (itoa (ctr-count-all))))']
# Exactly the user's GUI scenario: CTRAY, profile, width, A-B-C (one turn), Enter.
L += ["CTRAY", "SCADA_BASIC", "300", "0,0", "3000,0", "3000,2000", ""]
L += ['(princ (strcat "' + '\\n' + 'OBJ_AFTER=" (itoa (ctr-count-all))'
      ' " path=" (itoa (ctr-count-layer "SCADA-TRAY-PATH"))'
      ' " tray=" (itoa (ctr-count-layer "SCADA-TRAY"))))',
      "_SAVEAS", "DXF", "", str(out).replace("\\", "/"), "_QUIT", "Y", ""]
scr = work / "e2e2.scr"
scr.write_bytes(LF.join(L).encode("mbcs"))
rc, out_b, err, why = run_accore([r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe",
                                   "/i", str(base), "/s", str(scr), "/l", "en-US"], 180)
log = decode_console(out_b)
(work / "e2e2.stdout.log").write_text(log, encoding="utf-8")
print("rc", rc, why or "-", "dxf_exists", out.exists())
for line in log.splitlines():
    if any(k in line for k in ("CTRAY", "OBJ_", "[CTR]", "STRAIGHT DISPATCH", "profile=", "mode=",
                                "start=", "end=", "length=", "rung_count=", "renderer=",
                                "ENTERED", "RUNG CREATE")) \
       and "defun" not in line and "princ (strcat" not in line and "(_>" not in line:
        print("  ", line.strip()[:200])

if out.exists():
    import ezdxf
    from collections import Counter
    d = ezdxf.readfile(out)
    m = d.modelspace()
    tray = [e for e in m if e.dxf.layer == "SCADA-TRAY"]
    print("SCADA-TRAY entities:", dict(Counter(e.dxftype() for e in tray)))
    for e in tray:
        if e.dxftype() == "LWPOLYLINE":
            pts = [(round(p[0], 1), round(p[1], 1)) for p in e.get_points()]
            xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
            print("  LWPL bbox", min(xs), max(xs), min(ys), max(ys))
        elif e.dxftype() == "INSERT":
            print("  INSERT", e.dxf.name, e.dxf.insert, e.dxf.rotation, e.dxf.xscale)
