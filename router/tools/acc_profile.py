"""Profile-architecture integration test: two profiles' paths in ONE drawing,
run inside real accoreconsole on a scratch copy.  Checks block-name aliasing
(no collision), CROSS rejection for SCADA_BASIC, and no crash on unconfirmed
TEE dimensions.  Usage: <venv python> acc_profile.py <scratch_dir>
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
fw = lambda p: str(p).replace("\\", "/")


def inline(path):
    src = Path(path).read_text(encoding="utf-8")
    parts = [m.group(0) for m in TOKEN.finditer(src) if not m.group(0).startswith(";")]
    lines = [l.rstrip() for l in "".join(parts).splitlines() if l.strip()]
    return chr(10).join(l for l in lines if not l.lstrip().startswith("(load "))


from ctr_paths import rp  # BLOCK router dir; CTR_BLOCK_ROUTER_DIR overrides D:/BLOCK/router
inline_src = (inline(rp("cable_tray_router.lsp")) + chr(10)
              + inline(rp("tools/it_scenario.lsp")) + chr(10)
              + inline(rp("tools/it_profile.lsp")))
LF = chr(10)
scr = work / "p.scr"
scr.write_bytes((LF.join(["FILEDIA", "0", inline_src, "(it-profiles)", "_QUIT", "Y", ""])).encode("mbcs"))
rc, out, err, why = run_accore([r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe",
                                 "/i", str(base), "/s", str(scr), "/l", "en-US"], 240)
log = decode_console(out)
(work / "p.stdout.log").write_text(log, encoding="utf-8")
print("rc", rc, why or "-")
for line in log.splitlines():
    if any(k in line for k in ("[CTR]", "PROFILE_CHECK")) and "(defun" not in line and "princ" not in line:
        print("  ", line.strip()[:200])
