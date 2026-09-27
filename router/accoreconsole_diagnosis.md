# accoreconsole diagnosis

Executable: C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe (X.118.0.0)

## Run 1 (before user-profile repair)
- Command: accoreconsole.exe /i sample.dwg /readonly /s x.scr /l en-US (also without /i)
- Output: startup message box about acad2027.cfg, then
  `Unhandled Access Violation Writing 0x0000 Exception at 0h`; DXF not produced;
  same for the project's known-good sample.dwg and a script with only (princ "HELLO").
- Inside and outside the tool sandbox: identical -> sandbox NOT the cause.

## Run 2 (after user repaired HKCU profile / acad2027.cfg / acad.CUIX)
- Same executable and flags via dwg_batch_tool/scripts/convert_single.py (verified SAVEAS pattern).
- Result: rc 0, DXF_VALID for sample.dwg, SCADA_TRAY_{STRAIGHT,ELBOW,TEE,CROSS}.dwg, SDACA.dwg.
- No Access Violation, no acad2027.cfg message.

## Notes
- My first ad-hoc call hung because stdin was inherited; use Popen(stdin=DEVNULL) like
  convert_single.run_accore.
- SECURELOAD=1, TRUSTEDPATHS empty: (load) from D:\BLOCK is refused. Tests inline the source.
- UNDO/U have no effect in accoreconsole scripts (probe: entmake x3 in UNDO group, U -> count unchanged).
