"""Run cable_tray_router_tests.lsp headless through lisp_sim (no AutoCAD).
Usage: python tools/run_tests.py     exit code = number of failed checks
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from lisp_sim import Interp  # noqa: E402

it = Interp()
# strlen / substr are needed by the test helper only
from lisp_sim import Sym  # noqa: E402
it.builtins["STRLEN"] = lambda s: len(s)
it.builtins["SUBSTR"] = lambda s, i, n=None: s[i - 1:] if n is None else s[i - 1:i - 1 + n]
it.load_file(os.path.join(ROOT, "cable_tray_router.lsp"))
it.load_file(os.path.join(ROOT, "cable_tray_router_tests.lsp"))
it.load_file(os.path.join(ROOT, "cable_tray_router_offset_tests.lsp"))
fails = it.call("ctr-run-tests")
fails = it.call("ctr-run-offset-tests")  # cumulative: *T-FAIL* spans both suites
print()
sys.exit(int(fails or 0))
