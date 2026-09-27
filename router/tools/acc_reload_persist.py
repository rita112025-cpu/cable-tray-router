"""Confirms *CTR-CURRENT-PROFILE* survives a mid-session reload of the SAME
lisp file (simulating the user re-APPLOAD-ing after an edit), which is
exactly the scenario that caused RESOLVED PROFILE to silently fall back to
DEFAULT in the real GUI.  Sequence:
  1. load file
  2. CTRAY, answer profile=SCADA_BASIC, draw a 1-segment straight
  3. RELOAD the same file (a second (load ...) call, like a re-APPLOAD)
  4. CTRAYUPDATE-equivalent: run CTRAY again, answer BLANK at the profile
     prompt -- must resolve to SCADA_BASIC (not reset to DEFAULT).
Usage: <venv python> acc_reload_persist.py <scratch_dir>
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
# First CTRAY: explicitly pick SCADA_BASIC.
L += ["CTRAY", "SCADA_BASIC", "300", "0,0", "3000,0", ""]
L += ['(princ (strcat "' + '\\n' + 'AFTER-FIRST-CTRAY current=" *CTR-CURRENT-PROFILE*))']
# Simulate re-APPLOAD: load the SAME source again into the SAME session.
L += [router_src]
L += ['(princ (strcat "' + '\\n' + 'AFTER-RELOAD current=" *CTR-CURRENT-PROFILE*))']
# Second CTRAY: blank answer at the profile prompt (just press Enter).
L += ["CTRAY", "", "300", "5000,0", "8000,0", ""]
L += ["_QUIT", "Y", ""]
scr = work / "reload.scr"
scr.write_bytes(LF.join(L).encode("mbcs"))
rc, out_b, err, why = run_accore([r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe",
                                   "/i", str(base), "/s", str(scr), "/l", "en-US"], 180)
log = decode_console(out_b)
(work / "reload.stdout.log").write_text(log, encoding="utf-8")
print("rc", rc, why or "-")
for line in log.splitlines():
    if any(k in line for k in ("CTRAY", "AFTER-", "renderer=", "profile=", "mode=", "ENTERED", "[CTR][DEBUG] CTRAY DEBUG: profile")) \
       and "defun" not in line and "princ (strcat" not in line and "(_>" not in line:
        print("  ", line.strip()[:200])
