"""Full regression with NOTHING written under D:\\BLOCK.

    python router/tools/run_isolated_regression.py [--keep]

1. fingerprints (size, mtime, SHA-256) every file under D:\\BLOCK before the run
2. builds a scratch BLOCK root in the system temp dir:  <scratch>/router/{cable_tray_router.lsp, tools/it_*.lsp}
   (copied FROM THIS WORKTREE) and runs make_loaders.py --block-router-dir <scratch>/router
3. sets CTR_BLOCK_DIR / CTR_BLOCK_ROUTER_DIR to the scratch root and runs
   run_tests.py (router + CTOFFSET), test_loaders.py and every acc_*.py (each in its own scratch work dir)
4. fingerprints D:\\BLOCK again and fails if anything changed; deletes the scratch root (and the generated, git-ignored
   router/router_version.lsp if it did not exist before).  --keep leaves the scratch root for inspection.

Exit code 0 only if every step passed and D:\\BLOCK is unchanged.  The router core still READS fitting .dwg files from
D:/BLOCK/ (hard-coded *CTR-BLOCK-DIRS*); that is read only and is covered by the before/after fingerprint.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROUTER = HERE.parent
PROD = Path(r"D:\BLOCK")
STAMP = ROUTER / "router_version.lsp"


def fingerprint(root: Path) -> dict[str, tuple[int, int, str]]:
    out = {}
    for p in sorted(root.rglob("*")):
        if p.is_file():
            st = p.stat()
            out[str(p.relative_to(root))] = (st.st_size, st.st_mtime_ns, hashlib.sha256(p.read_bytes()).hexdigest())
    return out


def run(label: str, cmd: list[str], env: dict, results: list, log_dir: Path, timeout: int = 1500) -> None:
    print("\n=== %s" % label, flush=True)
    try:
        p = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
        rc, text = p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        rc, text = 124, "TIMEOUT"
    (log_dir / (label.replace(" ", "_") + ".log")).write_text(text, encoding="utf-8")
    print("\n".join(text.splitlines()[-12:]))
    print("--> %s (rc=%s)" % ("PASS" if rc == 0 else "FAIL", rc))
    results.append((label, rc == 0, text))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--only", default="", help="substring filter on acc_*.py names")
    args = ap.parse_args()

    stamp_existed = STAMP.exists()
    before = fingerprint(PROD)
    print("production D:\\BLOCK fingerprinted: %d files" % len(before))

    scratch = Path(tempfile.mkdtemp(prefix="ctr_regress_"))
    srouter = scratch / "router"
    (srouter / "tools").mkdir(parents=True)
    shutil.copy2(ROUTER / "cable_tray_router.lsp", srouter / "cable_tray_router.lsp")
    for f in (ROUTER / "tools").glob("it_*.lsp"):
        shutil.copy2(f, srouter / "tools" / f.name)
    env = dict(os.environ, CTR_BLOCK_DIR=str(scratch), CTR_BLOCK_ROUTER_DIR=str(srouter), PYTHONIOENCODING="utf-8")
    log_dir = scratch / "logs"
    log_dir.mkdir()
    print("CTR_BLOCK_DIR        =", env["CTR_BLOCK_DIR"])
    print("CTR_BLOCK_ROUTER_DIR =", env["CTR_BLOCK_ROUTER_DIR"])

    py = sys.executable
    results: list = []
    try:
        run("make_loaders", [py, str(HERE / "make_loaders.py"), "--block-router-dir", str(srouter)], env, results, log_dir)
        run("router+CTOFFSET unit", [py, str(HERE / "run_tests.py")], env, results, log_dir)
        run("test_loaders", [py, str(HERE / "test_loaders.py")], env, results, log_dir)
        for f in sorted(HERE.glob("acc_*.py")):
            if args.only in f.name:
                run(f.stem, [py, str(f), str(scratch / "work" / f.stem)], env, results, log_dir)
    finally:
        after = fingerprint(PROD)
        changed = sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))
        print("\n=== production D:\\BLOCK unchanged:", "YES" if not changed else "NO  " + str(changed))
        if args.keep:
            print("scratch kept:", scratch)
        else:
            shutil.rmtree(scratch, ignore_errors=True)
            if not stamp_existed:
                STAMP.unlink(missing_ok=True)

    print("\n=== SUMMARY")
    for label, ok, _ in results:
        print("  %-28s %s" % (label, "PASS" if ok else "FAIL"))
    print("  %-28s %s" % ("D:\\BLOCK unchanged", "PASS" if not changed else "FAIL"))
    return 0 if all(ok for _, ok, _ in results) and not changed else 1


if __name__ == "__main__":
    sys.exit(main())
