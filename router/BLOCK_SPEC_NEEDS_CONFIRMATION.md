# NEEDS_USER_CONFIRMATION (only what cannot be determined from the files)

Everything else (base point, orientation, centre, arm ends/takeoff, rail widths) was
measured from the DWG/DXF - see block_spec_measured.md.

1. **Tray widths offered** (WIDTH options). Router accepts any width and scales the
   fittings by width/BLOCK_WIDTH; default prompt value is 300. Which widths do you want?
2. **BLOCK_WIDTH basis.** 39/49/59 = rail centre-to-centre, inferred from SDACA.dwg insert
   scales (TEE gives 49.11 from 6.109; 49.0 assumed). Confirm that "Width 300" means
   rail centre-to-centre.
3. **SCADA_TRAY_CROSS symmetry.** Geometry is not exactly 90-degree symmetric (an extra
   open polyline at x=-29..-30 only). Router uses rotation 0. Confirm this is intended.
4. **Straight look.** Router draws Straight as a closed rectangle at +-WIDTH/2 on layer
   SCADA-TRAY (rail centre lines). Fittings have ~1*scale rail thickness (~7 mm at 300).
   Confirm this outline style is acceptable, or say if you want the Straight block instead.
5. **Undo.** Grouped with UNDO BEGIN/END, but accoreconsole ignores UNDO in scripts, so it
   could not be verified headless. Please test once in the GUI: CTRAYUPDATE, then U.
6. **Trusted location.** AutoCAD SECURELOAD=1 blocks (load) from D:\BLOCK. Add
   D:\BLOCK\router to Options > Files > Trusted Locations (or APPLOAD / startup suite).

## Profile SCADA_BASIC (added)

7. **SCADA_BASIC TEE dimensions.** D:\BLOCK\DEFAULT\SCADA_TRAY_TEE.dwg's geometry
   looks composite (3 nested arm-end radii + an embedded sub-block), not a single
   clean TEE. Router runs safely with a 0/scale-1 fallback and logs
   `NEEDS_USER_CONFIRMATION` every time this fitting is used, but this is NOT a
   real number - please confirm which sub-geometry is the actual TEE, its rail
   width, and its takeoff, or provide a clean re-export.
8. **SCADA_BASIC STRAIGHT.** Same "not a single stretchable tile" problem as
   Profile 1's straight block (see item 4 there); SCADA_BASIC currently renders
   Straight the same way Profile 1 does (a plain rectangle at +-width/2), NOT
   with SCADA_TRAY_STRAIGHT, until a usable single-width block/tile is confirmed.
9. **Folder-to-profile assignment.** I mapped D:\BLOCK\DEFAULT\ -> profile
   "SCADA_BASIC" and left D:\BLOCK\ (root) as profile "DEFAULT", specifically so
   Profile 1's already-verified behaviour is never touched. If you actually meant
   D:\BLOCK\DEFAULT\ to BE the "DEFAULT" profile's new block set, say so and I'll
   remeasure/re-point DEFAULT (which means re-validating its whole pipeline again,
   since the geometry there differs from what's tested today).

## Owner-requirement items (added 2026-10-03)

10. **Dynamic Block rung spacing 250 -> 225.** Owner maximum is 225 mm; the real block measures 250 mm
    (NON-COMPLIANT). The router already renders 225. The block itself must be updated in the GUI.
11. **ELBOW inner radius** (`ELBOW_INNER_RADIUS_REQUIRES_VERIFICATION`). Owner minimum 300 mm; candidate 264.5 mm
    from ELBOW_V2, block / tray-width mapping unconfirmed. Identify the block and width before judging it.
12. **Meaning of "yu-jiao" (residual angle)** in Appendix C (power <= 45, weak current <= 60): confirm whether it
    equals the CTOFFSET slope angle. Until then the angle check is a warning only.
13. **Cable minimum bending radius**: no cable type / OD / radius data is modelled; the check is NOT CHECKED.
