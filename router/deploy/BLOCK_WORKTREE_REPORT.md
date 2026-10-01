# D:\BLOCK worktree report (read-only inspection, nothing changed)

Generated 2026-10-01T08:34:44. `D:\BLOCK` is a git worktree: branch `fix/simplify-router-ux` at `5317504`.
It has uncommitted work that was left exactly as found (no discard / commit / stash / reset).

## git status (as found, before the loaders were created)
```
 M new/SCADA_TRAY_ELBOW_V2.dwg
 M router/README.md
 M router/block_spec_measured.md
 M router/cable_tray_router.lsp
?? router/checkpoint/
?? router/tools/ErrorReports/
```
After this work the only additions are the untracked `router/cable_tray_router_v1.lsp`, `router/cable_tray_router_v2.lsp` and `router/stable/`.

## router/cable_tray_router.lsp - hashes (sha256)
| version | sha256 |
|---|---|
| working file in D:\BLOCK\router | `1c21d15a66fce3fc1d53b58adfa4c1dbeb3cbfa9e5da02579be5c6ce4c8507d4` |
| 5317504 (branch base) | `06fbe7fa8b4c454063977133dcf213e856e8eb080fe136e03c567b117b22a92c` |
| 365645a (V1 STABLE baseline) | `4b046b0fac2ce7feb883e969abd7b3f457cfbfa6f67a2549691d2520e9bb3f95` |

The working file equals neither commit.

## Diffs (added / deleted lines)
- working tree vs 5317504:
```
-	-	new/SCADA_TRAY_ELBOW_V2.dwg
7	1	router/README.md
55	0	router/block_spec_measured.md
35	9	router/cable_tray_router.lsp
```
- working tree vs 365645a (V1 stable): `117	9	router/cable_tray_router.lsp`
- 5317504 vs 365645a (committed): `82	0	router/cable_tray_router.lsp`

Content of the uncommitted `cable_tray_router.lsp` change vs 5317504: `*CTR-SOURCE-ID*` text, profile-prompt aliases
(`*CTR-PROFILE-ALIASES*`, `ctr-resolve-profile-answer`, alias-aware `ctr-ask-profile`) and a new load banner. It is a UX change on top of the V2 profile
code, so it is **not** a V1 core.

## Observation: new/SCADA_TRAY_ELBOW_V2.dwg
| copy | sha256 (first 16) | arc pivot (block coords) |
|---|---|---|
| working file in D:\BLOCK\new | `8972f22568e8ec19` | (0, 0, 0) |
| committed blob (commit history: `101f297 2026-09-29 wip: SCADA_V2 profile skeleton (ELBOW_V2 hypothesis UNVERIFIED)`) | `31c7d4ce65900b78` | (-686.733, 521) |

The committed block and the uncommitted working-file block are different geometry (pivot translated by (-686.733, 521)). The Router ELBOW_V2
BASE_OFFSET (-576, 576) was written for the origin-pivot geometry; the integration worktree loads the translated one. This is consistent with the
Elbow rigid-translation finding fixed in `5669d5a`.

## What the loaders use
- V1 STABLE core: exported from `365645a` to `D:\BLOCK\router\stable\cable_tray_router.lsp` (read only). Not the working file above.
- `D:\BLOCK\router\cable_tray_router.lsp` is untouched; the `acc_*` tools keep pointing at it.
