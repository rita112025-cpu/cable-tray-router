# Measured block specs (from D:\BLOCK\*.dwg copies -> DXF via dwg_batch_tool converter)

All four DWGs are WBLOCK-style: geometry sits in model space, `$INSBASE = (0,0,0)`,
so the insertion base point is the file origin. `$INSUNITS = 4 (mm)`.
Originals were never modified (work on scratch copies only).

| Block | Arms (as drawn) | Fitting centre | Rail centre lines | Arm end (takeoff) | Extents |
|---|---|---|---|---|---|
| SCADA_TRAY_ELBOW | East + North | origin (0,0) (centre lines meet there) | x/y = ±19.5 (outer ±20) | 62 (E and N) | (-20,-20)..(62,62) |
| SCADA_TRAY_TEE   | main East-West, **branch SOUTH** | origin (0,0) | ±24.5 (outer ±25) | 67.5 main, 67.5 branch | (-67.5,-67.5)..(67.5,25) |
| SCADA_TRAY_CROSS | East, North, West, South | origin (0,0) | ±29.5 (outer ±30) | 72 (all four) | (-72,-72)..(72,72) |
| SCADA_TRAY_STRAIGHT | multi-width dynamic block | - | reference only | - | (-50,-32.5)..(50,50) |

Router reference orientation (see header of cable_tray_router.lsp):
ELBOW E+N, TEE main E-W + branch N, CROSS symmetric.
=> ELBOW `ROTATION_OFFSET` 0, TEE `ROTATION_OFFSET` 180 (block is drawn branch-South), CROSS 0.

## Scale (derived from the user's own drawing SDACA.dwg)
Blocks are inserted with uniform scale = tray width / BLOCK_WIDTH:

| SDACA insert | scale | 300 / scale | measured rail-centre width |
|---|---|---|---|
| Trary40x10-L (elbow) | 7.692 | 39.0 | 39 |
| Trary50x10-T (tee)   | 6.109 | 49.1 | 49 |
| Trary60x10-X (cross) | 5.085 | 59.0 | 59 |

Config uses BLOCK_WIDTH = 39 / 49 / 59; takeoff and base offset are stored in block
units and multiplied by the scale (e.g. elbow @300 -> scale 7.692, takeoff 476.9).

## Profile 2: SCADA_BASIC (from D:\BLOCK\DEFAULT\SCADA_TRAY_*.dwg, scratch copies)

D:\BLOCK\DEFAULT\ and D:\BLOCK\ contain THREE FILES WITH THE SAME NAMES
(SCADA_TRAY_STRAIGHT/ELBOW/TEE.dwg) but DIFFERENT geometry (confirmed: different
file hashes, different extents). Router now scopes the block directory per
profile (BLOCK_DIR) and inserts profile-scoped blocks under an aliased name
`<PROFILE>$<name>` in the drawing (e.g. `SCADA_BASIC$SCADA_TRAY_ELBOW`) so the
two never collide even when both profiles' paths exist in the same drawing.

| Block | Measured | Used? |
|---|---|---|
| ELBOW | Clean single figure. Arms East+North, rails +-14/15 (outer 15), arm end 57 -> BLOCK_WIDTH 29, TAKEOFF 57, ROTATION_OFFSET 0 (same E+N reference as Profile 1). | YES, config filled in |
| TEE   | The DXF is NOT one clean shape: 44 LWPOLYLINE incl. THREE nested arm-end radii (57/52/47) plus an embedded sub-block "Trary30x10-L", and rail curves appear on all 4 sides (N/E/S/W), not just main+branch. Looks like several variants/annotations exported on top of each other. | NEEDS_USER_CONFIRMATION: BLOCK_WIDTH/TAKEOFF/ROTATION_OFFSET/BASE_OFFSET left nil; router logs a warning and uses the existing 0/scale-1 test fallback rather than guess. |
| STRAIGHT | Byte-identical geometry to D:\BLOCK\SCADA_TRAY_STRAIGHT.dwg (305 LINE/55 ARC/12 LWPOLYLINE, ~100x82mm) - a multi-width reference figure, not a single stretchable tile. | STRAIGHT_MODE stays GEOMETRY (proven rectangle); STRAIGHT_BLOCK is wired in config but unused until a usable single-width tile is confirmed. |
| CROSS | Not provided for this profile (by design: SCADA_BASIC only ships STRAIGHT/ELBOW/TEE). | ENABLED = nil; router refuses with UNSUPPORTED_FITTING_FOR_PROFILE, never substitutes Tee+Tee. |

## GENERATED_LADDER (final): SCADA_BASIC Straight renderer

Decision (confirmed with the user): the real `SCADA_TRAY_STRAIGHT.dwg` ("750 tray")
IS a genuine AutoCAD Dynamic Block (full dependency graph traced from its own
DXF -- ACAD_ENHANCEDBLOCK -> BLOCKLINEARPARAMETER "Linear"/"Linear1" ->
BLOCKSTRETCHACTION/BLOCKARRAYACTION, all handle-linked to the 3 authoring
entities). But its Length/Width cannot be driven headlessly (accoreconsole has
no ActiveX object model and no graphical/crossing selection at all), and full
VBA/.NET automation isn't available on AutoCAD LT either way. So the Dynamic
Block stays a GUI-edited asset, and the Router renders Straight itself with
the SAME numbers the block's own authoring geometry uses:

| Quantity | Value | Source |
|---|---|---|
| Rail thickness | 20 | rail LWPOLYLINE: 110-90 = 20 |
| Width meaning | outer rail-to-rail envelope (same convention as everywhere else in the router) | authoring sample was outer width 750: rung span 750-2*20=710 matches the rung LWPOLYLINE's span (-620..90) exactly |
| Rung width | 40 | rung LWPOLYLINE: 145-105 = 40 |
| Rung spacing | 250 | BLOCKARRAYACTION group 141 on the array whose only linked object is the rung entity |
| First rung centre offset | 125 | rung LWPOLYLINE centre x in the authored sample |
| Confirmed widths | 150 / 300 / 450 / 600 / 750 | BLOCKLINEARPARAMETER "Linear1" (Distance2) 175=5, group 144 x5 |

Real-engine verification (tools/acc_ladder.py): 1000/2000/3000 long, width 750
(horizontal) and 1000 long width 300 (vertical) all produced rails at the
predicted offsets and 4/8/12/4 rungs respectively, at exactly the predicted
centre positions, on both axes.

CONFIRMED (2026-09-27, user's real AutoCAD GUI, block stretched to length 1000
via its own Grip -- screenshot supplied): 4 rungs, a visible gap between the
Base Grip and the first rung, and a visible gap between the last rung and the
End Grip arrow -- i.e. the real Dynamic Block leaves the far end open rather
than forcing a rung flush against it. This matches ctr-ladder-rung-centers'
"never overhang" rule exactly; no change needed. The rung count (4) and their
spacing also match the 125/375/625/875 prediction. Router's
STRAIGHT_RUNG_FIRST_OFFSET / STRAIGHT_RUNG_SPACING / never-overhang rule are
now confirmed against real GUI behaviour, not just the DXF authoring graph.

## Corrections to two earlier over-stated claims
- "AutoCAD LT does not support ActiveX" was wrong. Autodesk's own platform
  matrix: LT has LIMITED ActiveX Automation support, AutoLISP-hosted only (no
  VBA, no .NET). Whether `DynamicBlockReferenceProperty` is reachable that way
  on LT 2027 specifically is still unverified -- would need a real LT GUI test.
- "accoreconsole has no ActiveX at all" was stated too strongly from one
  negative test. What's actually confirmed: `(vlax-ename->vla-object ...)`
  returned nil in THIS session, without first confirming `(vl-load-com)` /
  `(vlax-get-acad-object)` succeeded on their own. Doesn't change the
  architecture decision (Router was never meant to depend on COM), but the
  claim itself should be "unable to verify", not "confirmed absent".
