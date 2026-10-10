# Cable Tray Router

AutoLISP tool for AutoCAD that turns a centre-line path into cable tray geometry (straights, elbows, tees, crosses) and
calculates vertical offsets, for the SCADA cable-tray drawings of the XDMRT project.
(AutoCAD 電纜線架佈設工具：由中心線路徑自動產生直線段 / 彎頭 / T 接 / 十字接頭，並提供垂直偏移計算。)

The router itself lives in [`router/`](router/). Start there:
[`router/README.md`](router/README.md) has the design notes, block profiles and CTOFFSET details.

## Repository layout

| Path | What it is |
|---|---|
| `router/cable_tray_router.lsp` | The router (single file). Config is at the top of the file. |
| `router/cable_tray_router_tests.lsp`, `router/cable_tray_router_offset_tests.lsp` | Pure-logic tests (no AutoCAD objects). |
| `router/tools/` | Test runners, AutoCAD Core Console integration scripts (`acc_*.py`), loader generator, LISP simulator. |
| `router/block_spec_measured.md`, `router/BLOCK_SPEC_NEEDS_CONFIRMATION.md` | Measured block geometry and open confirmation items. |
| `*.dwg` (repo root), `DEFAULT/`, `new/` | Fitting block drawings (`SCADA_TRAY_STRAIGHT/ELBOW/TEE/CROSS`) used by the profiles, and the `SDACA.dwg` sample. |

## Requirements

- AutoCAD (developed against AutoCAD 2027; integration tests use its `accoreconsole.exe`)
- Python 3.12 for the test tooling
- The router reads the fitting `.dwg` files from `D:/BLOCK/` (hard-coded in `*CTR-BLOCK-DIRS*`, read only)
- Some integration scripts expect `D:\github\ezdxf\dwg_batch_tool` (paths are set in `router/tools/`)

## Using it in AutoCAD

1. Add the router folder to AutoCAD's Trusted Locations (otherwise `SECURELOAD` blocks `(load ...)`).
2. Load `router/cable_tray_router.lsp` directly, or generate the APPLOAD loaders (`python router/tools/make_loaders.py`) and
   load `cable_tray_router_v1.lsp` / `cable_tray_router_v2.lsp`. Type `CTVER` to see which version is really loaded.
3. Run `CT` and pick the centre-line points (orthogonal segments only), then Enter. The centre line is kept on layer
   `SCADA-TRAY-PATH`; the generated tray goes on `SCADA-TRAY`.

| Command | Purpose |
|---|---|
| `CT` | Day-to-day: pick path points and generate tray with the current profile and width, no profile/width prompts |
| `CTSET` | Choose profile (`DEFAULT` / `SCADA_BASIC` / `SCADA_V2`) and width |
| `CTU` (`CTRAYUPDATE`) | Rebuild all generated tray from the path layer; only objects tagged `CTR_GEN` are ever deleted |
| `CTRAY` | Advanced: always asks profile and width |
| `CTOFFSET` | Vertical offset calculator (see below) |
| `CTINSPECT` | Read-only: print every node of the path network and how it was classified |
| `CTDEBUG`, `CTRELOAD`, `CTVER` | Debug output, re-read block definitions, show loaded version |

### CTOFFSET

Computes delta Z, angle, slope and true slope length from RUN or ANGLE input, checks available space against 15 / 22.5 / 30 / 45 deg,
and records an elevation model: `CENTER` / `BOTTOM` / `TOP` reference, tray height, `FLOOR_RELATIVE` / `ABSOLUTE` reference type,
and bottom / top elevations (B.EL / T.EL).

It also prints owner-requirement (Appendix C) checks as **warnings only**: offset angle, bottom height >= 2500 mm
(`FLOOR_RELATIVE` only), optional top clearance, and an explicit "cable bend radius not verified". It never blocks drawing.
Details: [`router/README.md`](router/README.md).

## Tests

```bash
python router/tools/run_tests.py                          # headless logic tests (no AutoCAD)
python router/tools/run_isolated_regression.py            # full regression: headless + loaders + every acc_*.py in AutoCAD Core Console
python router/tools/run_isolated_regression.py --only acc_ladder   # a single AutoCAD script
```

The isolated regression works in a scratch folder and fails if anything under `D:\BLOCK` changes.
Only `acc_ctoffset.py` and `acc_ladder.py` assert geometry or printed output; the other `acc_*.py` scripts are execution
(smoke) tests, so a pass there means "ran without error", not "geometry verified".
The loader test expects a clean, committed tree (the version stamp reports `+dirty` otherwise).

## Owner requirements and current status

- Ladder rung spacing is **225 mm** (owner maximum). The real Dynamic Block still measures 250 mm and is not yet updated.
- Unresolved items are tracked as GitHub issues:
  [#4](https://github.com/rita112025-cpu/cable-tray-router/issues/4) Dynamic Block 250 -> 225,
  [#5](https://github.com/rita112025-cpu/cable-tray-router/issues/5) ELBOW inner radius 264.5 mm vs owner minimum 300 mm,
  [#6](https://github.com/rita112025-cpu/cable-tray-router/issues/6) definition of the owner's "yu-jiao" (residual angle),
  [#7](https://github.com/rita112025-cpu/cable-tray-router/issues/7) Appendix C clearance route inspector.
