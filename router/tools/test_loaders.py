"""Engine tests for the APPLOAD loaders + CTVER (accoreconsole, blank scratch drawing, nothing saved).

    python router/tools/test_loaders.py

accoreconsole blocks (load) from untrusted folders (SECURELOAD), so the loaders are exercised with their documented test hook
(*CTR-LOADER-NOLOAD*): the cores / stamp are INLINED into the script exactly as the loader would load them, then the unmodified
generated loader runs.  One scenario runs the real (load) path to record how the loader fails when AutoCAD refuses.
Checks that D:/BLOCK/router/cable_tray_router.lsp is untouched.
"""
from __future__ import annotations

import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ACCORE = r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe"
BLOCK = Path(r"D:\BLOCK\router")
WORK = Path(__file__).resolve().parents[2] / "router"
V1_LOADER, V2_LOADER = BLOCK / "cable_tray_router_v1.lsp", BLOCK / "cable_tray_router_v2.lsp"
V1_CORE = BLOCK / "stable" / "cable_tray_router.lsp"
V2_CORE, STAMP = WORK / "cable_tray_router.lsp", WORK / "router_version.lsp"
UNTOUCHED = BLOCK / "cable_tray_router.lsp"


def strip_lisp(src: str) -> str:
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1])
            i = j + 1
        elif c == ";":
            while i < n and src[i] != "\n":
                i += 1
        else:
            out.append(c)
            i += 1
    return "\n".join(l.rstrip() for l in "".join(out).splitlines() if l.strip())


def run(parts: list[str], marker: str = "T:") -> str:
    work = Path(tempfile.mkdtemp(prefix="loader_test_"))
    script = "\n".join(["FILEDIA", "0"] + parts + ["_QUIT", "Y", ""])
    (work / "run.scr").write_bytes(script.encode("mbcs", errors="replace"))
    proc = subprocess.run([ACCORE, "/s", str(work / "run.scr"), "/l", "en-US"], stdin=subprocess.DEVNULL, capture_output=True,
                          timeout=600, cwd=str(work))
    data = proc.stdout
    text = data.decode("utf-16-le", "replace") if b"\x00" in data[:200] else data.decode("utf-8", "replace")
    return text


def lisp(path: Path) -> str:
    return strip_lisp(path.read_text(encoding="utf-8"))


def lines(text: str, prefix: str) -> list[str]:
    return [l.rstrip() for l in text.splitlines() if l.startswith(prefix)]


NOLOAD = "(setq *CTR-LOADER-NOLOAD* T)"
results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((name, bool(ok), detail))
    print(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail and not ok else ""))


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    before = hashlib.sha256(UNTOUCHED.read_bytes()).hexdigest()
    for f in (V1_LOADER, V2_LOADER, V1_CORE, V2_CORE, STAMP):
        check("exists: %s" % f, f.exists())
    for f in (V1_LOADER, V2_LOADER, STAMP):
        check("no backslash in generated %s" % f.name, "\\" not in f.read_text(encoding="utf-8"))
    stamp_text = STAMP.read_text(encoding="utf-8")
    commit = re.search(r'\*CTR-ROUTER-COMMIT\* "([^"]+)"', stamp_text).group(1)
    check("stamp commit is a clean short hash (no +dirty)", re.fullmatch(r"[0-9a-f]{7,}", commit) is not None, commit)
    v1blob = subprocess.run(["git", "-C", str(WORK.parent), "show", "365645a:router/cable_tray_router.lsp"], capture_output=True, check=True).stdout
    check("stable core == git blob 365645a", V1_CORE.read_bytes() == v1blob)
    check("stable core is read-only", not (V1_CORE.stat().st_mode & 0o200))
    check("V1 loader points at stable core", "D:/BLOCK/router/stable/cable_tray_router.lsp" in V1_LOADER.read_text(encoding="utf-8"))
    check("V2 loader points at the integration core + stamp",
          str(V2_CORE).replace("\\", "/") in V2_LOADER.read_text(encoding="utf-8") and str(STAMP).replace("\\", "/") in V2_LOADER.read_text(encoding="utf-8"))

    # S1 raw core, no loader
    t = run([lisp(V2_CORE), "(c:CTVER)"])
    check("S1 raw V2 core says UNSTAMPED", any("UNSTAMPED" in l for l in t.splitlines()))

    # S2 V1: a stale SCADA_V2 selection must be reset; V2 must not be selectable in the V1 core
    t = run([lisp(V1_CORE), '(setq *CTR-CURRENT-PROFILE* "SCADA_V2")', NOLOAD, lisp(V1_LOADER), "(c:CTVER)",
             '(princ (strcat (chr 10) "T:NAMES=" (vl-prin1-to-string (ctr-profile-names)) (chr 10)))'])
    out = "\n".join(l for l in t.splitlines() if not l.startswith(("(", " ")))
    check("S2 V1 announces 'Loaded: V1 STABLE'", "[CTRAY] Loaded: V1 STABLE" in out)
    check("S2 V1 announces source path", "[CTRAY] Source: D:/BLOCK/router/stable/cable_tray_router.lsp" in out)
    check("S2 V1 forces profile SCADA_BASIC (stale SCADA_V2 reset)", "[CTRAY] Profile: SCADA_BASIC" in out)
    check("S2 V1 commit 365645a", "[CTRAY] Router commit: 365645a" in out)
    check("S2 CTVER (V1): Version/Commit/Source lines", all(k in out for k in ("Version : V1 STABLE", "Commit  : 365645a", "Source  : D:/BLOCK/router/stable/cable_tray_router.lsp")))
    names = lines(t, "T:NAMES=")
    check("S2 V1 core has no SCADA_V2 profile", names and "SCADA_V2" not in names[0], str(names))

    # S3 V2
    t = run([lisp(V2_CORE), lisp(STAMP), NOLOAD, lisp(V2_LOADER), "(c:CTVER)",
             '(princ (strcat (chr 10) "T:NAMES=" (vl-prin1-to-string (ctr-profile-names)) (chr 10)))'])
    out = "\n".join(l for l in t.splitlines() if not l.startswith(("(", " ")))
    check("S3 V2 announces 'Loaded: SCADA_V2'", "[CTRAY] Loaded: SCADA_V2" in out)
    check("S3 V2 source is the integration core", "[CTRAY] Source: %s" % str(V2_CORE).replace("\\", "/") in out)
    check("S3 V2 profile SCADA_V2", "[CTRAY] Profile: SCADA_V2" in out)
    check("S3 V2 commit equals the generated stamp", "[CTRAY] Router commit: %s" % commit in out)
    check("S3 CTVER (V2): Version/Profile/Commit/Source", all(k in out for k in ("Version : SCADA_V2", "Profile : SCADA_V2", "Commit  : " + commit)))
    names = lines(t, "T:NAMES=")
    check("S3 V2 can select SCADA_V2", names and "SCADA_V2" in names[0], str(names))

    # S4 mixed session warning (V2 then V1)
    t = run([lisp(V2_CORE), lisp(STAMP), NOLOAD, lisp(V2_LOADER), lisp(V1_CORE), lisp(V1_LOADER)])
    out = "\n".join(l for l in t.splitlines() if not l.startswith(("(", " ")))
    check("S4 loading V1 after V2 warns about mixing", "WARNING: SCADA_V2 is already loaded" in out)

    # S5 missing core path -> clear failure, nothing announced as loaded
    bad = V1_LOADER.read_text(encoding="utf-8").replace("stable/cable_tray_router.lsp", "stable/DOES_NOT_EXIST.lsp")
    t = run([lisp(V1_CORE), strip_lisp(bad)])
    out = "\n".join(l for l in t.splitlines() if not l.startswith(("(", " ")))
    check("S5 missing core -> LOAD FAILED, no 'Loaded:' line", "LOAD FAILED (V1 STABLE): core not found" in out and "Loaded:" not in out)

    # S6 real (load): record behaviour when AutoCAD refuses (SECURELOAD) - must fail cleanly, never claim success
    t = run(["(setq *CTR-LOADER-NOLOAD* nil)", strip_lisp(V1_LOADER.read_text(encoding="utf-8"))])
    out = "\n".join(l for l in t.splitlines() if not l.startswith(("(", " ")))
    loaded = "[CTRAY] Loaded: V1 STABLE" in out
    failed = "LOAD FAILED (V1 STABLE)" in out
    check("S6 real (load) in accoreconsole either loads or fails with a clear message (never silent)", loaded != failed, out[-400:])
    print("      S6 observed:", "LOADED" if loaded else "BLOCKED/FAILED cleanly")

    after = hashlib.sha256(UNTOUCHED.read_bytes()).hexdigest()
    check("D:/BLOCK/router/cable_tray_router.lsp untouched", before == after)
    bad = [r for r in results if not r[1]]
    print("\n%d checks, %d failed" % (len(results), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
