"""Full end-to-end CTRAY test: types the command exactly as a GUI user would
(profile keyword, width, points, Enter), through the REAL c:CTRAY entry
point -- not it-mkpath-p, not a direct ctr-plan call. Confirms the profile
prompt -> ctr-ask-profile -> ctr-make-path -> ctr-regenerate -> ctr-draw-straight
chain end to end, and SAVEAS-DXF's the result so rail/rung counts can be
verified independently of any AutoLISP-side counting.
Usage: <venv python> acc_ctray_e2e.py <scratch_dir>
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
out = work / "ctray_e2e.dxf"
out.unlink(missing_ok=True)


def inline(path):
    src = Path(path).read_text(encoding="utf-8")
    parts = [m.group(0) for m in TOKEN.finditer(src) if not m.group(0).startswith(";")]
    lines = [l.rstrip() for l in "".join(parts).splitlines() if l.strip()]
    return chr(10).join(l for l in lines if not l.lstrip().startswith("(load "))


LF = chr(10)
L = ["FILEDIA", "0", inline(r"D:/BLOCK/router/cable_tray_router.lsp")]
L += ['(princ (strcat "' + '\\n' + 'OBJ_BEFORE=" (itoa (ctr-count-all))))']
# Exactly what a GUI user types: CTRAY, then the profile KEYWORD, then width,
# then a single straight segment (0,0)->(3000,0), then Enter to finish.
L += ["CTRAY", "SCADA_BASIC", "300", "0,0", "3000,0", ""]  # 3000mm straight, width 300, SCADA_BASIC
L += ['(princ (strcat "' + '\\n' + 'OBJ_AFTER=" (itoa (ctr-count-all))'
      ' " path=" (itoa (ctr-count-layer "SCADA-TRAY-PATH"))'
      ' " tray=" (itoa (ctr-count-layer "SCADA-TRAY"))))',
      "_SAVEAS", "DXF", "", str(out).replace("\\", "/"), "_QUIT", "Y", ""]
scr = work / "e2e.scr"
scr.write_bytes(LF.join(L).encode("mbcs"))
rc, out_b, err, why = run_accore([r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe",
                                   "/i", str(base), "/s", str(scr), "/l", "en-US"], 180)
log = decode_console(out_b)
(work / "e2e.stdout.log").write_text(log, encoding="utf-8")
print("rc", rc, why or "-", "dxf_exists", out.exists())
start = log.find("(princ")  # skip past the source echo of the FIRST princ form to real output
tail = log[log.find("CTRAY DEBUG: profile=") - 5:] if "CTRAY DEBUG: profile=" in log else log
for line in log.splitlines():
    if any(k in line for k in ("CTRAY DEBUG", "OBJ_", "[CTR]", "profile", "Cable Tray")) \
       and "defun" not in line and "princ (strcat" not in line:
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
            xs = [p[0] for p in pts]
            print("  LWPL bbox x", min(xs), max(xs), "width(x-span)", round(max(xs) - min(xs), 1))
