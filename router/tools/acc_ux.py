"""UX acceptance test matching the user's checklist:
  1. CT (fresh session)              -> SCADA_BASIC / 300
  2. CTSET width->450, then CT       -> SCADA_BASIC / 450
  3. reload the file, then CT        -> still SCADA_BASIC / 450
  4. CTU                             -> equivalent to CTRAYUPDATE
Usage: <venv python> acc_ux.py <scratch_dir>
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


router_src = inline(r"D:/BLOCK/router/cable_tray_router.lsp")
LF = chr(10)
L = ["FILEDIA", "0", router_src]

# Test 1: CT, fresh session -> SCADA_BASIC / 300, straight to "Specify start point".
L += ["CT", "0,0", "3000,0", ""]
L += ['(princ (strcat "' + '\\n' + 'T1 profile=" *CTR-CURRENT-PROFILE* " width=" (rtos *CTR-CURRENT-WIDTH* 2 0)))']

# Test 2: CTSET width -> 450, then CT should use 450 without asking.
L += ["CTSET", "", "450"]
L += ["CT", "0,5000", "3000,5000", ""]
L += ['(princ (strcat "' + '\\n' + 'T2 profile=" *CTR-CURRENT-PROFILE* " width=" (rtos *CTR-CURRENT-WIDTH* 2 0)))']

# Test 3: reload the SAME file (simulates re-APPLOAD), then CT -> still SCADA_BASIC/450.
L += [router_src]
L += ['(princ (strcat "' + '\\n' + 'T3-AFTER-RELOAD profile=" *CTR-CURRENT-PROFILE* " width=" (rtos *CTR-CURRENT-WIDTH* 2 0)))']
L += ["CT", "0,10000", "3000,10000", ""]
L += ['(princ (strcat "' + '\\n' + 'T3 profile=" *CTR-CURRENT-PROFILE* " width=" (rtos *CTR-CURRENT-WIDTH* 2 0)))']

# Test 4: CTU must equal CTRAYUPDATE (add a branch path directly, CTU should pick it up).
L += ['(ctr-make-path (list (list 3000.0 6000.0) (list 3000.0 5000.0)) 450.0 "SCADA_BASIC")']
L += ["CTU"]
L += ['(princ (strcat "' + '\\n' + 'T4 tray-objects=" (itoa (ctr-count-layer "SCADA-TRAY"))))']

L += ["_QUIT", "Y", ""]
scr = work / "ux.scr"
scr.write_bytes(LF.join(L).encode("mbcs"))
rc, out_b, err, why = run_accore([r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe",
                                   "/i", str(base), "/s", str(scr), "/l", "en-US"], 180)
log = decode_console(out_b)
(work / "ux.stdout.log").write_text(log, encoding="utf-8")
print("rc", rc, why or "-")
for line in log.splitlines():
    s = line.strip()
    if (s.startswith(("T1 ", "T2 ", "T3", "T4 ", "Cable Tray:", "Current profile:", "Current width:",
                       "cable_tray_router")) and "(_>" not in s and "defun" not in s and "princ" not in s) \
       or "[CTR][WARN]" in s or "[CTR][ERROR]" in s:
        print("  ", s[:200])
