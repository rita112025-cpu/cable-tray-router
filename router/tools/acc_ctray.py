"""Reproduce interactive CTRAY inside accoreconsole by feeding the prompts through the
script (width, points, Enter).  Scratch copy only.  usage: python acc_ctray.py <scratch> [mode]
mode: full (CTRAY) | pathonly (make path, no regenerate)"""
import sys
from pathlib import Path
sys.path.insert(0, r"D:\github\ezdxf\dwg_batch_tool\scripts"); sys.path.insert(0, str(Path(__file__).parent))
from common import decode_console
from convert_single import run_accore
from lisp_sim import TOKEN
import ezdxf, shutil
from collections import Counter
work = Path(sys.argv[1]); mode = sys.argv[2] if len(sys.argv) > 2 else "full"
work.mkdir(parents=True, exist_ok=True)
base = work / "base.dwg"; shutil.copy(r"D:\github\ezdxf\dwg_batch_tool\tests\fixtures\sample.dwg", base)
out = work / f"ctray_{mode}.dxf"; out.unlink(missing_ok=True)
def inline(path):
    src = Path(path).read_text(encoding="utf-8")
    parts = [m.group(0) for m in TOKEN.finditer(src) if not m.group(0).startswith(";")]
    return chr(10).join(l.rstrip() for l in "".join(parts).splitlines() if l.strip())
L = ["FILEDIA", "0", inline(r"D:/BLOCK/router/cable_tray_router.lsp")]
L += ['(princ (strcat "\nOBJ_BEFORE=" (itoa (ctr-count-all))))']
if mode in ("full", "freehand"):
    L += (["CTRAY", "300", "0,0", "3000,7", "3009,2000", "5000,2013", ""] if mode == "freehand" else ["CTRAY", "300", "0,0", "3000,0", "3000,2000", "5000,2000", ""])
else:
    L += ["(ctr-ensure-layers)", "(ctr-make-path (list (list 0.0 0.0) (list 3000.0 0.0) (list 3000.0 2000.0)) 300.0)"]
L += ['(princ (strcat "\nOBJ_AFTER=" (itoa (ctr-count-all)) " path=" (itoa (ctr-count-layer "SCADA-TRAY-PATH")) " tray=" (itoa (ctr-count-layer "SCADA-TRAY"))))',
      "_SAVEAS", "DXF", "", str(out).replace("\\", "/"), "_QUIT", ""]
scr = work / "c.scr"; scr.write_bytes(chr(10).join(L).encode("mbcs"))
rc, o, e, why = run_accore([r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe", "/i", str(base), "/s", str(scr), "/l", "en-US"], 240)
log = decode_console(o); (work / f"ctray_{mode}.log").write_text(log, encoding="utf-8")
print("rc", rc, why or "-", "dxf", out.exists())
for l in log.splitlines():
    if any(k in l for k in ("CTRAY", "[CTR]", "OBJ_")) and "(defun" not in l and "princ" not in l: print("  ", l.strip()[:170])
if out.exists():
    m = ezdxf.readfile(out).modelspace()
    print("  DXF layers:", dict(Counter((e.dxf.layer, e.dxftype()) for e in m if e.dxf.layer.startswith("SCADA"))))
