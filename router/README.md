# AutoCAD Cable Tray Router (MVP 0.1)

PATH = Source of Truth: centre-line path -> Network -> classify -> Straight/Elbow/Tee/Cross.

Files
- cable_tray_router.lsp        the router (CTRAY, CTRAYUPDATE); config at top of file
- cable_tray_router_tests.lsp  71 algorithm checks (pure sections)
- tools/lisp_sim.py, run_tests.py   run those tests headless: `python tools/run_tests.py`
- tools/acc_integration.py     end-to-end test inside accoreconsole (scratch copy of a DWG)
- block_spec_measured.md, BLOCK_SPEC_NEEDS_CONFIRMATION.md, accoreconsole_diagnosis.md

Use: add D:\BLOCK\router to Trusted Locations, then `(load "D:/BLOCK/router/cable_tray_router.lsp")`.
CTRAY: width, pick points (orthogonal only), Enter. CTRAYUPDATE: rebuild from SCADA-TRAY-PATH.
Fitting blocks are auto-loaded from *CTR-BLOCK-DIRS* (D:/BLOCK/) if missing in the drawing.
Only objects tagged XDATA CTR_GEN on SCADA-TRAY are ever deleted; paths are never touched.

## Block profiles

*CTR-PROFILES* holds one entry per non-default profile (name -> BLOCK_DIR,
STRAIGHT_MODE, FITTINGS). "DEFAULT" is not listed there on purpose: it is
whatever *CTR-FITTING-CONFIG* / *CTR-BLOCK-DIRS* already are at the top of the
file, untouched. `CTRAY` now asks `Profile [DEFAULT/SCADA_BASIC] <...>` before
width, and remembers the last choice for the session (*CTR-CURRENT-PROFILE*,
no registry). Each path stores its OWN profile+width in its CTR_PATH xdata, so
`CTRAYUPDATE` renders every path with the profile it was drawn with, not the
session's current one -- a drawing can mix DEFAULT and SCADA_BASIC paths.
A node whose arms come from two different profiles is rejected as
PROFILE_MISMATCH (same treatment as WIDTH_MISMATCH). A profile-scoped block is
inserted under `<PROFILE>$<name>` in the drawing (ctr-resolve-block-name) so
two profiles shipping a same-named file (D:\BLOCK\SCADA_TRAY_ELBOW.dwg vs
D:\BLOCK\DEFAULT\SCADA_TRAY_ELBOW.dwg) never collide in the block table.
`ctr-profile-supports-p` rejects an unsupported fitting (e.g. SCADA_BASIC/CROSS)
with `UNSUPPORTED_FITTING_FOR_PROFILE`, generating nothing at that node -- no
Tee+Tee substitution, no auto-repair.

## SCADA_BASIC Straight = GENERATED_LADDER

Not a rectangle, not the raw dynamic block: `ctr-draw-straight-ladder` draws
two rails + rungs directly with entmake, using the real block's OWN measured
numbers (rail thickness 20, rung width 40, spacing 250, first-rung offset
125, width = outer rail-to-rail, confirmed presets 150/300/450/600/750 -- see
block_spec_measured.md). The Dynamic Block itself is left for humans to edit
in the AutoCAD GUI; the router never tries to drive its parameters (it can't,
headlessly -- no ActiveX object model and no graphical selection in
accoreconsole, and no path to it in this codebase at all in AutoCAD LT either
way). `STRAIGHT_MODE` dispatch order per profile: BLOCK -> GENERATED_LADDER ->
GEOMETRY, each falling back to the next when it cannot draw.

## CTOFFSET elevation model and owner warnings

`CTOFFSET` geometry (delta Z, angle, slope, run, slope length) is unchanged and does not depend on the
owner rules. Metadata and owner checks are layered on top and only WARN.

- `ELEVATION_REFERENCE` = `CENTER` | `BOTTOM` | `TOP` says what the entered Z values mean; `TRAY_HEIGHT` (mm, default 150 = SCADA max outer depth, always editable) turns them into
  `START/END_CENTER_EL`, `START/END_BOTTOM_EL`, `START/END_TOP_EL` (stored as numbers).
- `REFERENCE_TYPE` = `FLOOR_RELATIVE` | `ABSOLUTE`. Stored and shown only; no datum conversion, and `FLOOR_RELATIVE` is never assumed to be +-0.00.
- Annotation (`ctr-offset-annotation`) prints `B.EL` and `T.EL` (Appendix C: tray elevation is the underside, two-point marking), never the centre line as the tray elevation.
- Checks (`ctr-offset-checks`, statuses PASS / WARNING / NOT CHECKED / N/A):
  - `OFFSET_ANGLE`: POWER > 45 deg, LOW_CURRENT / SCADA > 60 deg warns. The owner term is "yu-jiao" (residual angle), not yet confirmed equal to the CTOFFSET slope angle, so it is a warning marked "Interpretation pending".
  - `BOTTOM_HEIGHT`: BOTTOM_EL < 2500 mm warns, only for `FLOOR_RELATIVE`; `ABSOLUTE` is NOT CHECKED.
  - `TOP_CLEARANCE`: only when the user gives it. >= 300 PASS; 150-299 warns (difficult-condition range); < 150 warns (below minimum). The slab level is never guessed.
  - `CABLE_BEND_RADIUS_CHECK`: always NOT CHECKED (no cable data); an offset adds "Cable minimum bending radius has not been verified."
- Not in `CTOFFSET` (belongs to a future route inspector): clearances to water pipes / equipment / other trays, multi-layer spacing, joints above trays, wall/column distance.

Tray ladder rung spacing is 225 mm (owner maximum); the real Dynamic Block still measures 250 mm and is non-compliant. See `block_spec_measured.md`.
Tests: `python tools/run_tests.py` (headless) and `tools/acc_ctoffset.py` (AutoCAD Core Console prompt flow).
