"""GENERATED_LADDER integration test: real AutoCAD engine, straights at
1000/2000/3000 (horizontal, width 750) plus one vertical (width 300).
Usage: <venv python> acc_ladder.py <scratch_dir>
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


inline_src = (inline(r"D:/BLOCK/router/cable_tray_router.lsp") + chr(10)
              + inline(r"D:/BLOCK/router/tools/it_scenario.lsp") + chr(10)
              + inline(r"D:/BLOCK/router/tools/it_ladder.lsp"))
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
