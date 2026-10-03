"""CTOFFSET smoke test in the real AutoCAD Core Console (blank scratch drawing, nothing saved).

Drives the interactive prompts (elevation reference / reference type / tray height / system type /
top clearance) and checks that the printed report carries the bottom/top elevations and the owner
warnings.  The pure logic is covered headless by run_tests.py; this proves the prompt flow
(getstring / getreal / strcase / substr) works inside AutoCAD.
Usage: <venv python> acc_ctoffset.py <scratch_dir>      exit code 0 = all checks passed
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
router_src = inline(rp("cable_tray_router.lsp"))
LF = chr(10)
L = ["FILEDIA", "0", router_src]

# O1: ANGLE mode, BOTTOM reference, FLOOR_RELATIVE, h=150, 3300 -> 2700, 65 deg, SCADA, top clearance 250, skip space
#     prompts: Mode / Elevation reference / Reference type / Tray height / Start / End / Offset angle /
#              System type / Top clearance / Available horizontal space
L += ["CTOFFSET", "ANGLE", "BOTTOM", "FLOOR_RELATIVE", "150", "3300", "2700", "65", "SCADA", "250", ""]
# O2: RUN mode, CENTER reference, ABSOLUTE, h=150, level 2000 -> 2000, run 1000, top clearance skipped
L += ["CTOFFSET", "RUN", "CENTER", "ABSOLUTE", "150", "2000", "2000", "1000", ""]
# O3: invalid reference is rejected with a message, nothing computed
L += ["CTOFFSET", "ANGLE", "MIDDLEX", "", "", ""]
L += ["_QUIT", "Y", ""]
scr = work / "ctoffset.scr"
scr.write_bytes(LF.join(L).encode("mbcs"))
rc, out_b, err, why = run_accore([r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe",
                                   "/i", str(base), "/s", str(scr), "/l", "en-US"], 180)
log = decode_console(out_b)
(work / "ctoffset.stdout.log").write_text(log, encoding="utf-8")
print("rc", rc, why or "-")

# keep only real output lines (drop the echoed source / prompts)
out = [l.strip() for l in log.splitlines() if "defun" not in l and "(_>" not in l]
text = "\n".join(out)
checks = [
    ("O1 Start B/C/T EL (BOTTOM 3300, h150)", "Start B/C/T EL  : 3300.00 / 3375.00 / 3450.00 mm"),
    ("O1 End B/C/T EL", "End B/C/T EL    : 2700.00 / 2775.00 / 2850.00 mm"),
    ("O1 reference type shown", "Reference Type  : FLOOR_RELATIVE"),
    ("O1 angle 65 > SCADA 60 warns", "WARNING: Offset angle exceeds Appendix C weak-current guidance of 60 deg."),
    ("O1 interpretation pending", "Interpretation pending"),
    ("O1 top clearance 250 in difficult range", "difficult-condition range"),
    ("O1 cable bend radius unverified", "WARNING: Cable minimum bending radius has not been verified."),
    ("O2 ABSOLUTE bottom not checked", "REFERENCE_TYPE is not FLOOR_RELATIVE"),
    ("O2 level: no vertical offset", "No vertical offset required."),
    ("O3 invalid reference rejected", "Invalid elevation reference, reference type or tray height"),
]
bad = 0
for name, needle in checks:
    ok = needle in text
    bad += (not ok)
    print("  %s  %s" % ("PASS" if ok else "FAIL", name))
if "[CTR][ERROR]" in text or "error:" in text.lower():
    print("  FAIL  console reported an error")
    bad += 1
sys.exit(bad)
