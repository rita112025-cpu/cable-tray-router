;;; ====================================================================
;;; cable_tray_router.lsp  --  AutoCAD Cable Tray Router (MVP 0.1)
;;;
;;; Commands : CTRAY, CTRAYUPDATE
;;; Principle: PATH = Source of Truth
;;;            centre-line path -> Network (Node/Segment) -> classify
;;;            -> plan (Straight / Elbow / Tee / Cross) -> AutoCAD geometry
;;;
;;; Layers   : SCADA-TRAY-PATH  (centre lines, user data, never modified)
;;;            SCADA-TRAY       (generated output, tagged with XDATA CTR_GEN)
;;;
;;; No ActiveX / COM / vl-* / vla-*.  Plain AutoLISP only.
;;; Scope MVP: 2D, orthogonal (0/90/180/270), one width per junction,
;;;            no elevation, no collision, no reducer.
;;;
;;; File layout
;;;   1. Settings and central fitting config   (edit ONLY here)
;;;   2. Logging + small utilities
;;;   3. Angle / direction engine              (pure)
;;;   4. Network engine                        (pure)
;;;   5. Classification + rotation engine      (pure)
;;;   6. Takeoff engine + Straight geometry    (pure)
;;;   7. Planner                               (pure, returns ops + errors)
;;;   8. AutoCAD layer (entmake, ssget, undo)  (needs AutoCAD)
;;;   9. Commands
;;;
;;; Sections 1-7 make no AutoCAD calls and are unit-tested by
;;; cable_tray_router_tests.lsp.
;;;
;;; Direction convention (dir index): 0=East 1=North 2=West 3=South
;;;
;;; Fitting REFERENCE orientation (what the router assumes a block looks
;;; like when inserted with rotation 0; ROTATION_OFFSET adapts real blocks):
;;;   ELBOW : arms to East and North
;;;   TEE   : main run East-West, branch to North
;;;   CROSS : arms E/N/W/S (symmetric)
;;;   Insert point = fitting centre = network node (+ optional BASE_OFFSET)
;;; ====================================================================

;;; ---------------------------------------------------------------
;;; 1. SETTINGS AND CENTRAL FITTING CONFIG
;;; ---------------------------------------------------------------
(setq *CTR-VERSION*       "0.1.1-debug")
(setq *CTR-SOURCE-ID*     "cable_tray_router.lsp @2026-09-27T-ladder-debug")
(setq *CTR-LAYER-PATH*    "SCADA-TRAY-PATH")
(setq *CTR-LAYER-TRAY*    "SCADA-TRAY")
(setq *CTR-LAYER-COLORS*  '(("SCADA-TRAY-PATH" . 4) ("SCADA-TRAY" . 3)))  ; ACI fallback
;; Project BIM colour standard (XDMRT-TK01-PLN-MDC-0002-1 p.33): "SCADA系統(ESC)"
;; = RGB(12,100,47).  True colour, not an ACI approximation -- packed as
;; R*65536+G*256+B = 12*65536+100*256+47 = 812079 for DXF group 420. (This
;; exact value already appears as group 420 on the "750 tray" Straight block's
;; own entities, confirming it's the correct standard, not a guess.)
(setq *CTR-LAYER-TRUECOLOR* '(("SCADA-TRAY" . 812079)))
(setq *CTR-APP-GEN*       "CTR_GEN")   ; XDATA app on every generated object
(setq *CTR-APP-PATH*      "CTR_PATH")  ; XDATA app on path (holds width)
(setq *CTR-DEFAULT-WIDTH* 300.0)       ; NEEDS_USER_CONFIRMATION: width options
(setq *CTR-TOL*           0.001)       ; coordinate tolerance (drawing units)
(setq *CTR-ANGTOL*        0.0001)      ; angle tolerance (radians)
(if (not (boundp (quote *CTR-DEBUG*))) (setq *CTR-DEBUG* nil))  ; OFF by default; C:CTDEBUG toggles, survives reload

;;; Fitting table.  One entry per (TYPE, WIDTH).  WIDTH nil = any width.
;;; The blocks are drawn once at a reference size and INSERTED WITH A UNIFORM
;;; SCALE = tray WIDTH / BLOCK_WIDTH (this is how the user's SDACA.dwg uses
;;; them: Trary40x10-L x7.692, Trary50x10-T x6.109, Trary60x10-X x5.085
;;; -> 300/7.692=39, 300/6.109=49.1, 300/5.085=59).
;;;   BLOCK           block name
;;;   WIDTH           tray width this entry applies to (nil = any, scaled)
;;;   BLOCK_WIDTH     tray width the block is drawn for = distance between the
;;;                   two rail centre lines, in BLOCK units
;;;   SCALE           optional explicit insertion scale; overrides WIDTH/BLOCK_WIDTH.
;;;                   Use per-width entries (WIDTH 300 / 450 / 600, own BLOCK,
;;;                   SCALE, TAKEOFF) so scaling is NOT an engineering rule.
;;;   TAKEOFF         node -> end of fitting arm, in BLOCK units (x scale)
;;;   BRANCH_TAKEOFF  TEE branch arm, BLOCK units (nil = same as TAKEOFF)
;;;   ROTATION_OFFSET degrees CCW to rotate the drawn block so it matches the
;;;                   router reference orientation (nil -> 0, warns)
;;;   BASE_OFFSET     (dx dy) block base point -> fitting centre, BLOCK units
;;; nil values = NEEDS_USER_CONFIRMATION: router uses a TEST fallback
;;; (0 / scale 1) and logs it.  Later this can be filled from a CSV.
;;;
;;; MEASURED from D:\BLOCK\SCADA_TRAY_*.dwg (via DXF, see block_spec_measured.md):
;;;   ELBOW : arms East+North, centre = origin, rails x/y = +-19.5, arm end 62
;;;   TEE   : main E-W, branch drawn SOUTH (ref = North -> offset 180),
;;;           rails +-24.5, arm ends 67.5 (main and branch)
;;;   CROSS : 4 arms, rails +-29.5, arm end 72
(setq *CTR-FITTING-CONFIG*
  '(
    (("TYPE" . "ELBOW") ("BLOCK" . "SCADA_TRAY_ELBOW") ("WIDTH" . nil)
     ("BLOCK_WIDTH" . 39.0) ("TAKEOFF" . 62.0) ("BRANCH_TAKEOFF" . nil)
     ("ROTATION_OFFSET" . 0.0) ("BASE_OFFSET" 0.0 0.0))
    (("TYPE" . "TEE") ("BLOCK" . "SCADA_TRAY_TEE") ("WIDTH" . nil)
     ("BLOCK_WIDTH" . 49.0) ("TAKEOFF" . 67.5) ("BRANCH_TAKEOFF" . 67.5)
     ("ROTATION_OFFSET" . 180.0) ("BASE_OFFSET" 0.0 0.0))
    (("TYPE" . "CROSS") ("BLOCK" . "SCADA_TRAY_CROSS") ("WIDTH" . nil)
     ("BLOCK_WIDTH" . 59.0) ("TAKEOFF" . 72.0) ("BRANCH_TAKEOFF" . nil)
     ("ROTATION_OFFSET" . 0.0) ("BASE_OFFSET" 0.0 0.0))
   )
)

;;; Where to load fitting block definitions from when the drawing does not
;;; contain them yet (they are WBLOCK files: <dir><BLOCKNAME>.dwg).
(setq *CTR-BLOCK-DIRS* '("D:/BLOCK/"))

;;; ---------------------------------------------------------------
;;; 1b. BLOCK PROFILES  (which fitting blocks CTRAY renders with)
;;; ---------------------------------------------------------------
;;; A profile is an alist:
;;;   ("BLOCK_DIR"      . dir-or-nil)      ; nil = share *CTR-BLOCK-DIRS*
;;;   ("STRAIGHT_MODE"  . "GEOMETRY"|"BLOCK")
;;;   ("STRAIGHT_BLOCK" . name-or-nil)     ; used when STRAIGHT_MODE = BLOCK
;;;   ("FITTINGS"       . fitting-config-list)  ; same shape as *CTR-FITTING-CONFIG*,
;;;                                              ; entry ("ENABLED" . nil) = fitting
;;;                                              ; not supported by this profile
;;; "DEFAULT" is NOT listed here on purpose: unless a path's PROFILE is a name
;;; found in *CTR-PROFILES*, the router falls back to today's untouched
;;; behaviour (*CTR-FITTING-CONFIG* / *CTR-BLOCK-DIRS* as-is) -- Profile 1 is
;;; guaranteed unmodified by construction, not by copying its numbers here.
;;;
;;; SCADA_BASIC: STRAIGHT/ELBOW/TEE/CROSS.  Blocks measured from
;;; D:\BLOCK\DEFAULT\SCADA_TRAY_*.dwg (scratch copies, see block_spec_measured.md):
;;;   ELBOW : clean single figure, arms East+North, rails +-14/15, arm end 57
;;;           -> BLOCK_WIDTH 29, TAKEOFF 57, ROTATION_OFFSET 0 (same ref as DEFAULT)
;;;   TEE   : the DXF is NOT a single clean shape (44 LWPOLYLINE incl. 3 nested
;;;           arm-end radii 57/52/47 AND an embedded "Trary30x10-L" sub-block) --
;;;           looks like several variants/annotations exported on top of each
;;;           other. NEEDS_USER_CONFIRMATION: BLOCK_WIDTH/TAKEOFF/ROTATION_OFFSET
;;;           left nil on purpose (router logs + uses safe fallback, never guesses).
;;;   STRAIGHT: byte-identical geometry to D:\BLOCK\SCADA_TRAY_STRAIGHT.dwg (305
;;;           LINE/55 ARC/12 LWPOLYLINE, ~100x82mm) -- a multi-width reference
;;;           figure, not a single stretchable tile (same conclusion as before).
;;;           STRAIGHT_MODE stays GEOMETRY (proven rectangle) until a usable
;;;           single-width block/tile is confirmed.
;;; The block DIRECTORY is scoped per profile (BLOCK_DIR) precisely because
;;; D:\BLOCK\DEFAULT\ and D:\BLOCK\ contain DIFFERENT geometry under the SAME
;;; three names -- ctr-resolve-block-name aliases every profile-scoped block
;;; as "<PROFILE>$<name>" in the drawing's block table so the two never collide
;;; even when paths from both profiles exist in the same drawing.
(setq *CTR-PROFILES*
  (list
    (cons "SCADA_BASIC"
      (list
        (cons "BLOCK_DIR" "D:/BLOCK/DEFAULT/")
        ;; STRAIGHT: the real block ("750 tray", D:\BLOCK\DEFAULT\SCADA_TRAY_STRAIGHT.dwg)
        ;; IS a genuine AutoCAD Dynamic Block (confirmed via its DXF dependency
        ;; graph: ACAD_ENHANCEDBLOCK -> BLOCKLINEARPARAMETER "Linear"/"Linear1" ->
        ;; BLOCKSTRETCHACTION/BLOCKARRAYACTION, see block_spec_measured.md). But
        ;; its Length/Width parameters cannot be driven headlessly: accoreconsole
        ;; has no ActiveX object model at all (`vlax-ename->vla-object` -> nil,
        ;; confirmed) and no graphical/crossing selection either (`ssget "_C"`
        ;; over the WHOLE drawing returned nil), so neither COM nor a scripted
        ;; grip-stretch can reach it there. AutoCAD LT itself only has LIMITED
        ;; ActiveX support (AutoLISP-hosted only, per Autodesk's own platform
        ;; matrix) -- real, full VBA/.NET automation is not available on LT
        ;; regardless. Router therefore treats the Dynamic Block as a
        ;; human/GUI-edited asset and renders Straight itself: GENERATED_LADDER
        ;; draws rails+rungs directly from the block's OWN confirmed authoring
        ;; geometry (same numbers "750 tray" uses), so this is measured, not
        ;; guessed. Width here means the same thing as everywhere else in the
        ;; router: outer rail-to-rail envelope (confirmed: the authoring sample
        ;; was at outer width 750, rail thickness 20 each side -> rung span
        ;; 750-2*20=710, centreline-to-centreline 750-20=730, both match the
        ;; DXF exactly). Confirmed discrete widths (the block's own Distance2
        ;; preset list): 150/300/450/600/750.
        (cons "STRAIGHT_MODE" "GENERATED_LADDER")
        (cons "STRAIGHT_BLOCK" "SCADA_TRAY_STRAIGHT")     ; kept for GUI/manual use, unused by the router
        (cons "STRAIGHT_RAIL_THICKNESS" 20.0)              ; confirmed (rail LWPOLYLINE: 110-90=20)
        (cons "STRAIGHT_RUNG_WIDTH" 40.0)                  ; confirmed (rung LWPOLYLINE: 145-105=40)
        (cons "STRAIGHT_RUNG_SPACING" 250.0)                ; confirmed (BLOCKARRAYACTION group 141)
        (cons "STRAIGHT_RUNG_FIRST_OFFSET" 125.0)          ; confirmed (authoring sample + GUI stretch test @ length 1000)
        ;; NEEDS_USER_CONFIRMATION: what happens at the FAR end of a segment --
        ;; does the real dynamic block drop a rung that would overhang past the
        ;; stretched end, or always force one exactly at the end?  Not yet
        ;; verified against a real GUI stretch test.  Router uses the
        ;; conservative rule "never let a rung overhang the segment" until this
        ;; is confirmed (see ctr-ladder-rung-centers).
        (cons "STRAIGHT_SUPPORTED_WIDTHS" (list 150.0 300.0 450.0 600.0 750.0))
        (cons "FITTINGS"
          (list
            (list (cons "TYPE" "ELBOW") (cons "BLOCK" "SCADA_TRAY_ELBOW") (cons "WIDTH" nil)
                  (cons "BLOCK_WIDTH" 29.0) (cons "TAKEOFF" 57.0) (cons "BRANCH_TAKEOFF" nil)
                  (cons "ROTATION_OFFSET" 0.0) (cons "BASE_OFFSET" (list 0.0 0.0)))
            ;; CONFIRMED by user (real AutoCAD measurement of
            ;; D:\BLOCK\DEFAULT\SCADA_TRAY_TEE.dwg): BLOCK_WIDTH=29,
            ;; MAIN_TAKEOFF=57, BRANCH_TAKEOFF=42.  Branch is drawn NORTH in
            ;; this block (out.zip DXF: branch curves at local y=+45..+57,
            ;; main rail spans the full -57..57 at y=-14/-15) -- matches the
            ;; router's own reference orientation exactly, so ROTATION_OFFSET
            ;; = 0 here (unlike the DEFAULT profile's root Tee, whose branch is
            ;; drawn SOUTH and needs +180).
            (list (cons "TYPE" "TEE") (cons "BLOCK" "SCADA_TRAY_TEE") (cons "WIDTH" nil)
                  (cons "BLOCK_WIDTH" 29.0) (cons "TAKEOFF" 57.0)
                  ;; CONFIRMED via real AutoCAD exploded geometry: the user's
                  ;; first hand-measurement (42) was NOT the actual connection
                  ;; plane -- the fitting's branch fillet genuinely extends to
                  ;; local reference distance 57 (scaled 589.6552 at width 300),
                  ;; same as the main takeoff. Corrected 42 -> 57.
                  (cons "BRANCH_TAKEOFF" 57.0)
                  (cons "ROTATION_OFFSET" 0.0) (cons "BASE_OFFSET" (list 0.0 0.0)))
            ;; CONFIRMED via real AutoCAD measurement of scratch copies of
            ;; D:\BLOCK\DEFAULT\SCADA_TRAY_CROSS.dwg (out.zip DXF): the 4
            ;; corner fillet curves (NW/NE/SE/SW) all reach their arm tip at
            ;; local (+-57, +-57) -- i.e. TAKEOFF = 57 in BOTH X and Y, not
            ;; just assumed symmetric -- with rail band 14/15 (thickness ~1,
            ;; centre 14.5) at every tip, same as Elbow/Tee -> BLOCK_WIDTH 29.
            ;; Arms sit at native East/North/West/South already (no offset
            ;; needed to match the router's own CROSS reference, which is
            ;; itself rotation-symmetric: ctr-cross-rotation always 0).
            (list (cons "TYPE" "CROSS") (cons "BLOCK" "SCADA_TRAY_CROSS") (cons "WIDTH" nil)
                  (cons "BLOCK_WIDTH" 29.0) (cons "TAKEOFF" 57.0) (cons "BRANCH_TAKEOFF" nil)
                  (cons "ROTATION_OFFSET" 0.0) (cons "BASE_OFFSET" (list 0.0 0.0)))
          ))))
    ;; SCADA_V2: D:\BLOCK\new\SCADA_TRAY_*_V2.dwg -- a DIFFERENT design style
    ;; from SCADA_BASIC's reference-symbol blocks: real large-radius bend
    ;; geometry (actual ARC entities, not a small scaled symbol), so BASE_OFFSET
    ;; is non-zero here (block origin does NOT sit at the fitting's corner).
    ;; STRAIGHT_V2 IS confirmed byte-identical to the already-measured "750
    ;; tray" ("750 tray" AcDbDynamicBlockTrueName / DXF coords match exactly),
    ;; so it reuses that GENERATED_LADDER config unchanged.
    ;; ELBOW_V2 measured from its own DXF (arcs + tangent lines): bend centre
    ;; at local (-686.73,521.0) exactly equals both arms' centreline
    ;; intersection (confirmed: horizontal arm centreline y=(510.16+531.84)/2
    ;; =521.0; vertical arm centreline x=(-675.9-697.57)/2=-686.735) -- so
    ;; BASE_OFFSET = -(that point) = (686.73,-521.0). Arms sit at East+South in
    ;; the raw block (not East+North), so ROTATION_OFFSET=90 to match the
    ;; router's reference. BLOCK_WIDTH/TAKEOFF below are a STARTING HYPOTHESIS
    ;; from hand-measured arc radii (outer rail radius ~887.5, inner ~264.5,
    ;; centre-to-centre ~622.9) -- NOT yet confirmed by a real-engine join-delta
    ;; test the way Elbow/Tee/Cross were for SCADA_BASIC; do that before
    ;; trusting this for real drawings (see block_spec_measured.md).
    (cons "SCADA_V2"
      (list
        (cons "BLOCK_DIR" "D:/BLOCK/new/")
        (cons "STRAIGHT_MODE" "GENERATED_LADDER")
        (cons "STRAIGHT_BLOCK" "SCADA_TRAY_STRAIGHT_V2")
        (cons "STRAIGHT_RAIL_THICKNESS" 20.0)
        (cons "STRAIGHT_RUNG_WIDTH" 40.0)
        (cons "STRAIGHT_RUNG_SPACING" 250.0)
        (cons "STRAIGHT_RUNG_FIRST_OFFSET" 125.0)
        (cons "STRAIGHT_SUPPORTED_WIDTHS" (list 150.0 300.0 450.0 600.0 750.0))
        (cons "FITTINGS"
          (list
            ;; HYPOTHESIS, pending real-engine 0mm confirmation:
            (list (cons "TYPE" "ELBOW") (cons "BLOCK" "SCADA_TRAY_ELBOW_V2") (cons "WIDTH" nil)
                  (cons "BLOCK_WIDTH" 622.93) (cons "TAKEOFF" 878.933) (cons "BRANCH_TAKEOFF" nil)
                  (cons "ROTATION_OFFSET" 90.0) (cons "BASE_OFFSET" (list 686.73 -521.0)))
            ;; NEEDS_USER_CONFIRMATION: TEE_V2/CROSS_V2 use a chamfered-rect
            ;; style (not simple corner fillets) -- not yet measured/verified.
            ;; Left unconfigured (nil) rather than guessed; router safely falls
            ;; back to scale=1/takeoff=0 with a loud warning if these are used.
            (list (cons "TYPE" "TEE") (cons "BLOCK" "SCADA_TRAY_TEE_V2") (cons "WIDTH" nil)
                  (cons "BLOCK_WIDTH" nil) (cons "TAKEOFF" nil) (cons "BRANCH_TAKEOFF" nil)
                  (cons "ROTATION_OFFSET" nil) (cons "BASE_OFFSET" nil))
            (list (cons "TYPE" "CROSS") (cons "BLOCK" "SCADA_TRAY_CROSS_V2") (cons "WIDTH" nil)
                  (cons "BLOCK_WIDTH" nil) (cons "TAKEOFF" nil) (cons "BRANCH_TAKEOFF" nil)
                  (cons "ROTATION_OFFSET" nil) (cons "BASE_OFFSET" nil))
          ))))))

(if (not (boundp (quote *CTR-CURRENT-PROFILE*)))
  (setq *CTR-CURRENT-PROFILE* "SCADA_BASIC"))   ; day-to-day default; only on the session's
                                                 ; FIRST load -- a reload (e.g. re-APPLOAD after
                                                 ; an edit) must NOT wipe out whatever the user
                                                 ; already picked (CT / CTSET) this session.
(if (not (boundp (quote *CTR-CURRENT-WIDTH*)))
  (setq *CTR-CURRENT-WIDTH* 300.0))
(setq *CTR-LAST-PROFILE-ANSWER* nil)

(defun ctr-profile-names (/ p out)
  (setq out (list "DEFAULT"))
  (foreach p *CTR-PROFILES* (setq out (append out (list (car p)))))
  out)

(defun ctr-join (lst sep / s first x)
  (setq first T)
  (foreach x lst (setq s (if first x (strcat s sep x)) first nil))
  s)

(defun ctr-get-profile (name) (cdr (assoc name *CTR-PROFILES*)))

;; entry present for TYPE with ("ENABLED" . nil) => unsupported; absent entry
;; or entry without an ENABLED key => supported (default).  "DEFAULT" (or any
;; unregistered profile) always supports everything -- unchanged behaviour.
(defun ctr-profile-supports-p (profile type / prof fits entry pair)
  (cond
    ((or (null profile) (= profile "DEFAULT")) T)
    (T
     (setq prof (ctr-get-profile profile))
     (if (null prof)
       T                          ; unknown profile name: do not silently block
       (progn
         (setq fits (cdr (assoc "FITTINGS" prof)))
         (setq entry nil)
         (foreach e fits (if (and (null entry) (= (ctr-cfg-get e "TYPE") type)) (setq entry e)))
         (if (null entry)
           nil                    ; no entry at all for this type = not supported
           (progn
             (setq pair (assoc "ENABLED" entry))
             (not (and pair (null (cdr pair)))))))))))

;; drawing-safe block name: profile-scoped blocks get a "<PROFILE>$" prefix so
;; they never collide with another profile's identically-named source file.
(defun ctr-resolve-block-name (profile stem / prof)
  (setq prof (ctr-get-profile profile))
  (if (and prof (cdr (assoc "BLOCK_DIR" prof)))
    (strcat profile "$" stem)
    stem))

(defun ctr-profile-block-dirs (profile / prof d)
  (setq prof (ctr-get-profile profile))
  (setq d (if prof (cdr (assoc "BLOCK_DIR" prof))))
  (if d (list d) *CTR-BLOCK-DIRS*))

(defun ctr-profile-fittings (profile / prof)
  (setq prof (ctr-get-profile profile))
  (if prof (cdr (assoc "FITTINGS" prof)) *CTR-FITTING-CONFIG*))

(defun ctr-profile-straight-mode (profile / prof v)
  (setq prof (ctr-get-profile profile))
  (setq v (if prof (cdr (assoc "STRAIGHT_MODE" prof))))
  (if v v "GEOMETRY"))


;;; ---------------------------------------------------------------
;;; 2. LOGGING + UTILITIES
;;; ---------------------------------------------------------------
(setq *CTR-LOG* nil)
(setq *CTR-QUIET* nil)     ; T = store log lines but do not print (tests)
(setq *CTR-WARNED* nil)    ; keys already warned once in this run
(setq *CTR-PENDING-STEM* nil)   ; set by ctr-plan-node just before calling avail-fn
(setq *CTR-PENDING-DIRS* nil)

(defun ctr-take (lst n / out)
  (while (and lst (> n 0))
    (setq out (cons (car lst) out) lst (cdr lst) n (1- n)))
  (reverse out))

(defun ctr-log (level msg / line)
  (setq line (strcat "[CTR][" level "] " msg))
  (setq *CTR-LOG* (cons line *CTR-LOG*))
  (if (> (length *CTR-LOG*) 500)
    (setq *CTR-LOG* (ctr-take *CTR-LOG* 500)))
  (if (and (not *CTR-QUIET*) (or (/= level "DEBUG") *CTR-DEBUG*))
    (princ (strcat "\n" line)))
  nil)

(defun ctr-warn-once (key level msg)
  (if (not (member key *CTR-WARNED*))
    (progn (setq *CTR-WARNED* (cons key *CTR-WARNED*))
           (ctr-log level msg)))
  nil)

(defun ctr-2d (p) (list (float (car p)) (float (cadr p))))

(defun ctr-fmt-pt (p)
  (strcat "(" (rtos (car p) 2 3) ", " (rtos (cadr p) 2 3) ")"))

(defun ctr-pt-dist (p q / dx dy)
  (setq dx (- (car q) (car p)) dy (- (cadr q) (cadr p)))
  (sqrt (+ (* dx dx) (* dy dy))))

(defun ctr-pt-eq (p q) (< (ctr-pt-dist p q) *CTR-TOL*))

(defun ctr-has-duplicates (lst)
  (cond ((null lst) nil)
        ((member (car lst) (cdr lst)) T)
        (T (ctr-has-duplicates (cdr lst)))))

(defun ctr-remove-first (item lst / out done x)
  (foreach x lst
    (if (and (not done) (equal x item))
      (setq done T)
      (setq out (cons x out))))
  (reverse out))

;; selection sort of points by distance from origin (lists are tiny)
(defun ctr-sort-pts (pts origin / out best p)
  (while pts
    (setq best (car pts))
    (foreach p (cdr pts)
      (if (< (ctr-pt-dist p origin) (ctr-pt-dist best origin))
        (setq best p)))
    (setq out (cons best out))
    (setq pts (ctr-remove-first best pts)))
  (reverse out))

;;; Fitting config access -------------------------------------------
(defun ctr-cfg-get (entry key) (cdr (assoc key entry)))

(defun ctr-width-in-list-p (width widths / hit w)
  (foreach w widths (if (< (abs (- w width)) *CTR-TOL*) (setq hit T)))
  hit)

(defun ctr-get-fitting-config (type width / hit e w)
  ;; pass 1: exact width match, pass 2: entry with WIDTH = nil
  (foreach e *CTR-FITTING-CONFIG*
    (if (and (null hit) (= (ctr-cfg-get e "TYPE") type))
      (progn
        (setq w (ctr-cfg-get e "WIDTH"))
        (if (and w width (< (abs (- w width)) *CTR-TOL*))
          (setq hit e)))))
  (if (null hit)
    (foreach e *CTR-FITTING-CONFIG*
      (if (and (null hit)
               (= (ctr-cfg-get e "TYPE") type)
               (null (ctr-cfg-get e "WIDTH")))
        (setq hit e))))
  hit)

;; insertion scale = tray width / BLOCK_WIDTH  (1.0 test fallback + loud log)
(defun ctr-get-scale (type width / cfg bw)
  (setq cfg (ctr-get-fitting-config type width))
  (setq bw (if cfg (ctr-cfg-get cfg "BLOCK_WIDTH")))
  (if (and cfg (ctr-cfg-get cfg "SCALE"))
    (float (ctr-cfg-get cfg "SCALE"))          ; explicit per-width scale wins
  (if (or (null bw) (null width))
    (progn
      (ctr-warn-once (strcat type "|SCALE") "WARN"
        (strcat "NEEDS_USER_CONFIRMATION:
" type
                " BLOCK_WIDTH not configured.
Temporary test value: scale = 1."))
      1.0)
    (/ (float width) bw))))

;; kind = "MAIN" or "BRANCH".  Result is in DRAWING units (config value x scale).
;; Unknown -> 0.0 test fallback + loud log.
(defun ctr-get-takeoff (type width kind / cfg v)
  (setq cfg (ctr-get-fitting-config type width))
  (cond
    ((null cfg)
     (ctr-warn-once (strcat type "|CFG") "WARN"
       (strcat "NEEDS_USER_CONFIRMATION:\n" type
               " fitting config not found.\nTemporary test value = 0."))
     0.0)
    (T
     (setq v nil)
     (if (= kind "BRANCH") (setq v (ctr-cfg-get cfg "BRANCH_TAKEOFF")))
     (if (null v) (setq v (ctr-cfg-get cfg "TAKEOFF")))
     (if (null v)
       (progn
         (ctr-warn-once (strcat type "|TAKEOFF") "WARN"
           (strcat "NEEDS_USER_CONFIRMATION:\n" type
                   " TAKEOFF not configured.\nTemporary test value = 0."))
         0.0)
       (* (float v) (ctr-get-scale type width))))))

(defun ctr-get-rotation-offset (type width / cfg v)
  (setq cfg (ctr-get-fitting-config type width))
  (setq v (if cfg (ctr-cfg-get cfg "ROTATION_OFFSET")))
  (if (null v)
    (progn
      (ctr-warn-once (strcat type "|ROT") "WARN"
        (strcat "NEEDS_USER_CONFIRMATION:\n" type
                " ROTATION_OFFSET (block base direction) not configured.\n"
                "Temporary test value = 0 deg."))
      0.0)
    (float v)))

(defun ctr-get-base-offset (type width / cfg v)
  (setq cfg (ctr-get-fitting-config type width))
  (setq v (if cfg (ctr-cfg-get cfg "BASE_OFFSET")))
  (if (null v)
    (progn
      (ctr-warn-once (strcat type "|BASE") "WARN"
        (strcat "NEEDS_USER_CONFIRMATION:\n" type
                " BASE_OFFSET (block base point -> fitting centre) not configured.\n"
                "Temporary test value = (0 0)."))
      (list 0.0 0.0))
    (list (* (float (car v)) (ctr-get-scale type width))
          (* (float (cadr v)) (ctr-get-scale type width)))))

;;; ---------------------------------------------------------------
;;; 3. ANGLE / DIRECTION ENGINE
;;; ---------------------------------------------------------------
(defun ctr-angle-normalize (a / tp)
  (setq tp (* 2.0 pi))
  (setq a (rem a tp))
  (if (< a 0.0) (setq a (+ a tp)))
  (if (>= a (- tp 0.000000001)) (setq a 0.0))
  a)

;; dir index of p1->p2: 0=E 1=N 2=W 3=S, nil if zero length or not orthogonal
(defun ctr-direction (p1 p2 / dx dy a k)
  (setq dx (- (car p2) (car p1)) dy (- (cadr p2) (cadr p1)))
  (if (< (sqrt (+ (* dx dx) (* dy dy))) *CTR-TOL*)
    nil
    (progn
      (setq a (ctr-angle-normalize (atan dy dx)))
      (setq k (fix (+ (/ a (/ pi 2.0)) 0.5)))
      (if (< (abs (- a (* k (/ pi 2.0)))) *CTR-ANGTOL*)
        (rem k 4)
        nil))))

(defun ctr-dir-angle (d) (* d (/ pi 2.0)))
(defun ctr-dir-opposite (d) (rem (+ d 2) 4))
(defun ctr-dir-name (d) (nth d '("EAST" "NORTH" "WEST" "SOUTH")))

;; same axis (opposite OR same direction)
(defun ctr-is-collinear (d1 d2) (= 0 (rem (abs (- d1 d2)) 2)))
;; truly opposite (a straight run through a node)
(defun ctr-is-opposite (d1 d2) (= d2 (ctr-dir-opposite d1)))
;; perpendicular
(defun ctr-is-orthogonal (d1 d2) (= 1 (rem (abs (- d1 d2)) 2)))

(defun ctr-segment-length (p1 p2) (ctr-pt-dist p1 p2))

;; project q onto the dominant axis from p (same result as ORTHO): the router
;; only supports 0/90/180/270, so freehand picks are snapped, not rejected.
(defun ctr-snap-ortho (p q / dx dy)
  (setq dx (- (car q) (car p)) dy (- (cadr q) (cadr p)))
  (if (>= (abs dx) (abs dy))
    (list (car q) (cadr p))
    (list (car p) (cadr q))))

;;; ---------------------------------------------------------------
;;; 4. NETWORK ENGINE
;;;   path : (width (pt pt ...))               pt = (x y)
;;;   raw  : (p1 p2 width profile)
;;;   node : (id x y)
;;;   seg  : (id n1 n2 length dir width profile)   dir = n1->n2 dir index or nil
;;;   net  : (nodes segs)
;;; ---------------------------------------------------------------

;; parameter s along a->b of point p if p lies strictly inside a-b, else nil
(defun ctr-pt-on-seg-interior (p a b / len ux uy dx dy s d)
  (setq len (ctr-pt-dist a b))
  (if (< len *CTR-TOL*)
    nil
    (progn
      (setq ux (/ (- (car b) (car a)) len) uy (/ (- (cadr b) (cadr a)) len))
      (setq dx (- (car p) (car a)) dy (- (cadr p) (cadr a)))
      (setq s (+ (* dx ux) (* dy uy)))
      (setq d (abs (- (* dx uy) (* dy ux))))
      (if (and (< d *CTR-TOL*) (> s *CTR-TOL*) (< s (- len *CTR-TOL*)))
        s
        nil))))

;; crossing point of two perpendicular orthogonal raw segments, strictly
;; interior to both; else nil
(defun ctr-cross-point (r o / da db x)
  (setq da (ctr-direction (car r) (cadr r)) db (ctr-direction (car o) (cadr o)))
  (if (and da db (ctr-is-orthogonal da db))
    (progn
      (setq x (if (= 0 (rem da 2))
                (list (car (car o)) (cadr (car r)))     ; r horizontal
                (list (car (car r)) (cadr (car o)))))   ; r vertical
      (if (and (ctr-pt-on-seg-interior x (car r) (cadr r))
               (ctr-pt-on-seg-interior x (car o) (cadr o)))
        x
        nil))
    nil))

(defun ctr-split-one (r cands / pts prev out c)
  (setq pts (ctr-sort-pts cands (car r)))
  (setq prev (car r))
  (foreach c pts
    (if (> (ctr-pt-dist prev c) *CTR-TOL*)
      (progn (setq out (cons (list prev c (caddr r) (nth 3 r)) out))
             (setq prev c))))
  (if (> (ctr-pt-dist prev (cadr r)) *CTR-TOL*)
    (setq out (cons (list prev (cadr r) (caddr r) (nth 3 r)) out)))
  (reverse out))

;; split raw segments where another segment ends on them (T) or crosses (X)
(defun ctr-split-raw (raws / out i j r o cands x)
  (setq i 0)
  (foreach r raws
    (setq cands nil j 0)
    (foreach o raws
      (if (/= i j)
        (progn
          (if (ctr-pt-on-seg-interior (car o) (car r) (cadr r))
            (setq cands (cons (car o) cands)))
          (if (ctr-pt-on-seg-interior (cadr o) (car r) (cadr r))
            (setq cands (cons (cadr o) cands)))
          (setq x (ctr-cross-point r o))
          (if x (setq cands (cons x cands)))))
      (setq j (1+ j)))
    (setq out (append out (ctr-split-one r cands)))
    (setq i (1+ i)))
  out)

;; paths -> raw segments (split at T / X junctions).
;; path = (width pts) [legacy, profile defaults to "DEFAULT"] or
;;        (width profile pts) [profile-aware].  Either shape is accepted so
;;        every existing test and drawing keeps working unchanged.
(defun ctr-build-segments (paths / raws path w profile pts a b)
  (foreach path paths
    (setq w (car path))
    (if (>= (length path) 3)
      (setq profile (cadr path) pts (caddr path))
      (setq profile "DEFAULT" pts (cadr path)))
    (if (< (length pts) 2)
      (ctr-log "ERROR" "PATH_TOO_SHORT: a path needs at least 2 points.")
      (progn
        (setq a (car pts))
        (foreach b (cdr pts)
          (if (< (ctr-pt-dist a b) *CTR-TOL*)
            (ctr-log "WARN" (strcat "ZERO_LENGTH: duplicate point at "
                                    (ctr-fmt-pt a) " ignored."))
            (setq raws (cons (list a b w profile) raws)))
          (setq a b)))))
  (ctr-split-raw (reverse raws)))

(defun ctr-node-pt (node) (list (cadr node) (caddr node)))

(defun ctr-find-node (nodes pt / hit n)
  (foreach n nodes
    (if (and (null hit) (ctr-pt-eq (ctr-node-pt n) pt))
      (setq hit (car n))))
  hit)

;; raw segments -> nodes (unique points, ids 0..n-1)
(defun ctr-build-nodes (raws / nodes id r p)
  (setq id 0)
  (foreach r raws
    (foreach p (list (car r) (cadr r))
      (if (null (ctr-find-node nodes p))
        (progn
          (setq nodes (cons (list id (car p) (cadr p)) nodes))
          (setq id (1+ id))))))
  (reverse nodes))

(defun ctr-build-network (paths / raws nodes segs sid r n1 n2 key seen)
  (setq raws (ctr-build-segments paths))
  (setq nodes (ctr-build-nodes raws))
  (setq sid 0)
  (foreach r raws
    (setq n1 (ctr-find-node nodes (car r)) n2 (ctr-find-node nodes (cadr r)))
    (setq key (list (min n1 n2) (max n1 n2)))
    (if (member key seen)
      (ctr-log "WARN" (strcat "DUPLICATE_SEGMENT: overlapping segment at "
                              (ctr-fmt-pt (car r)) " ignored."))
      (progn
        (setq seen (cons key seen))
        (setq segs (cons (list sid n1 n2
                               (ctr-segment-length (car r) (cadr r))
                               (ctr-direction (car r) (cadr r))
                               (caddr r) (nth 3 r))
                         segs))
        (setq sid (1+ sid)))))
  (list nodes (reverse segs)))

(defun ctr-node-segs (nid segs / out s)
  (foreach s segs
    (if (or (= (nth 1 s) nid) (= (nth 2 s) nid))
      (setq out (cons s out))))
  (reverse out))

(defun ctr-node-degree (nid segs) (length (ctr-node-segs nid segs)))

;; direction of segment as seen leaving node nid (nil if non-orthogonal)
(defun ctr-seg-out-dir (seg nid)
  (cond ((null (nth 4 seg)) nil)
        ((= nid (nth 1 seg)) (nth 4 seg))
        (T (ctr-dir-opposite (nth 4 seg)))))

;;; ---------------------------------------------------------------
;;; 5. CLASSIFICATION + ROTATION ENGINE
;;; ---------------------------------------------------------------
(defun ctr-unsupported (reason)
  (list (cons "TYPE" "UNSUPPORTED_GEOMETRY") (cons "REASON" reason)))

;; rotation in quarter turns (CCW) from the reference orientation
;; ELBOW reference arms: East(0) + North(1)
(defun ctr-elbow-rotation (d1 d2)
  (cond ((= (rem (+ d1 1) 4) d2) d1)
        ((= (rem (+ d2 1) 4) d1) d2)
        (T nil)))
;; TEE reference: main E-W, branch North(1)
(defun ctr-tee-rotation (branch) (rem (+ branch 3) 4))
;; CROSS: symmetric
(defun ctr-cross-rotation () 0)

(defun ctr-find-opposite-pair (dirs / out a b)
  (foreach a dirs
    (foreach b dirs
      (if (and (null out) (< a b) (ctr-is-opposite a b))
        (setq out (list a b)))))
  out)

(defun ctr-widths-differ (ss / w s out)
  (setq w (nth 5 (car ss)))
  (foreach s ss
    (if (> (abs (- (nth 5 s) w)) *CTR-TOL*) (setq out T)))
  out)

(defun ctr-seg-profile (seg) (if (>= (length seg) 7) (nth 6 seg) "DEFAULT"))

(defun ctr-profiles-differ (ss / p s out)
  (setq p (ctr-seg-profile (car ss)))
  (foreach s ss (if (/= (ctr-seg-profile s) p) (setq out T)))
  out)

;; -> alist: TYPE, DEGREE, DIRS, [MAIN, BRANCH], [ROT], or REASON
;; TYPE in END STRAIGHT ELBOW TEE CROSS UNSUPPORTED_GEOMETRY
(defun ctr-classify-node (nid segs / ss dirs deg d1 d2 main br d)
  (setq ss (ctr-node-segs nid segs) deg (length ss))
  (setq dirs (mapcar '(lambda (s) (ctr-seg-out-dir s nid)) ss))
  (cond
    ((= deg 0) (ctr-unsupported "ISOLATED_NODE"))
    ((> deg 4) (ctr-unsupported "MORE_THAN_4_SEGMENTS"))
    ((member nil dirs) (ctr-unsupported "NON_ORTHOGONAL_SEGMENT"))
    ((ctr-has-duplicates dirs) (ctr-unsupported "OVERLAPPING_SEGMENTS"))
    ((ctr-widths-differ ss) (ctr-unsupported "WIDTH_MISMATCH (reducer not supported)"))
    ((ctr-profiles-differ ss) (ctr-unsupported "PROFILE_MISMATCH (mixed block profiles at node)"))
    ((= deg 1)
     (list (cons "TYPE" "END") (cons "DEGREE" 1) (cons "DIRS" dirs)))
    ((= deg 2)
     (setq d1 (car dirs) d2 (cadr dirs))
     (cond
       ((ctr-is-opposite d1 d2)
        (list (cons "TYPE" "STRAIGHT") (cons "DEGREE" 2) (cons "DIRS" dirs)
              (cons "MAIN" dirs)))
       ((ctr-is-orthogonal d1 d2)
        (list (cons "TYPE" "ELBOW") (cons "DEGREE" 2) (cons "DIRS" dirs)
              (cons "ROT" (ctr-elbow-rotation d1 d2))))
       (T (ctr-unsupported "DEGREE2_GEOMETRY_UNRESOLVED"))))
    ((= deg 3)
     (setq main (ctr-find-opposite-pair dirs))
     (if (null main)
       (ctr-unsupported "TEE_NO_MAIN_RUN")
       (progn
         (foreach d dirs (if (not (member d main)) (setq br d)))
         (list (cons "TYPE" "TEE") (cons "DEGREE" 3) (cons "DIRS" dirs)
               (cons "MAIN" main) (cons "BRANCH" br)
               (cons "ROT" (ctr-tee-rotation br))))))
    ((= deg 4)
     (if (and (member 0 dirs) (member 1 dirs) (member 2 dirs) (member 3 dirs))
       (list (cons "TYPE" "CROSS") (cons "DEGREE" 4) (cons "DIRS" dirs)
             (cons "ROT" (ctr-cross-rotation)))
       (ctr-unsupported "CROSS_GEOMETRY_ERROR")))
    (T (ctr-unsupported "UNCLASSIFIED"))))

;;; ---------------------------------------------------------------
;;; 6. TAKEOFF ENGINE + STRAIGHT GEOMETRY
;;; ---------------------------------------------------------------
;; Shorten p1-p2 by tk1 at p1 and tk2 at p2.
;; Returns (a b) or nil when tk1 + tk2 >= length  (SEGMENT_TOO_SHORT).
;;   usableStart = p1 + u*tk1      usableEnd = p2 - u*tk2
(defun ctr-trim-segment (p1 p2 tk1 tk2 / len ux uy)
  (setq len (ctr-pt-dist p1 p2))
  (if (or (< len *CTR-TOL*) (>= (+ tk1 tk2) (- len *CTR-TOL*)))
    nil
    (progn
      (setq ux (/ (- (car p2) (car p1)) len) uy (/ (- (cadr p2) (cadr p1)) len))
      (list (list (+ (car p1) (* ux tk1)) (+ (cadr p1) (* uy tk1)))
            (list (- (car p2) (* ux tk2)) (- (cadr p2) (* uy tk2)))))))

;; takeoff to apply at the node-end of a segment arm (arm-dir leaving node)
;; np = node plan (see ctr-plan-node)
(defun ctr-arm-takeoff (np arm-dir / info type)
  (setq info (nth 1 np) type (cdr (assoc "TYPE" info)))
  (cond
    ((= type "TEE")
     (if (member arm-dir (cdr (assoc "MAIN" info))) (nth 2 np) (nth 3 np)))
    ((or (= type "ELBOW") (= type "CROSS")) (nth 2 np))
    (T 0.0)))

;; four corners of the tray outline for centre segment p1-p2 (any direction)
(defun ctr-straight-corners (p1 p2 width / len ux uy nx ny h)
  (setq len (ctr-pt-dist p1 p2) h (/ width 2.0))
  (setq ux (/ (- (car p2) (car p1)) len) uy (/ (- (cadr p2) (cadr p1)) len))
  (setq nx (- uy) ny ux)
  (list (list (+ (car p1) (* nx h)) (+ (cadr p1) (* ny h)))
        (list (+ (car p2) (* nx h)) (+ (cadr p2) (* ny h)))
        (list (- (car p2) (* nx h)) (- (cadr p2) (* ny h)))
        (list (- (car p1) (* nx h)) (- (cadr p1) (* ny h)))))

;;; ---------------------------------------------------------------
;;; 7. PLANNER  (pure: network -> ops + errors)
;;;   op  : ("STRAIGHT" p1 p2 width segId profile)
;;;         ("FITTING" type blockName insertPt rotationRad nodeId scale)
;;;   err : (code pt message)
;;; ---------------------------------------------------------------
;; node plan: (nid info takeoffMain takeoffBranch op errs profile)
;; Profile-aware: *CTR-FITTING-CONFIG* is temporarily bound to the node's
;; profile's own fitting list while looking up cfg/takeoff/scale/rotation/base
;; (all four ctr-get-* helpers just read that global, unchanged) and restored
;; before returning -- "DEFAULT" (or an unregistered profile) is a no-op swap,
;; so Profile 1's behaviour is untouched by construction.
(defun ctr-plan-node (node segs avail-fn / nid pt info type ss w profile
                                          saved-cfg saved-dirs stem blk
                                          tkm tkb rot off bo ins op errs)
  (setq nid (car node) pt (ctr-node-pt node))
  (setq ss (ctr-node-segs nid segs))
  (setq profile (if ss (ctr-seg-profile (car ss)) "DEFAULT"))
  (setq info (ctr-classify-node nid segs))
  (setq type (cdr (assoc "TYPE" info)))
  (setq tkm 0.0 tkb 0.0)
  (cond
    ((= type "UNSUPPORTED_GEOMETRY")
     (setq errs (list (list "UNSUPPORTED_GEOMETRY" pt (cdr (assoc "REASON" info))))))
    ((or (= type "END") (= type "STRAIGHT")) nil)
    ((not (ctr-profile-supports-p profile type))
     (setq errs (list (list "UNSUPPORTED_FITTING_FOR_PROFILE" pt
                       (strcat "profile=" profile " fitting=" type))))
     (setq info (list (cons "TYPE" "UNSUPPORTED_GEOMETRY")
                       (cons "REASON" (strcat "UNSUPPORTED_FITTING_FOR_PROFILE profile="
                                              profile " fitting=" type)))))
    (T
     (setq saved-cfg *CTR-FITTING-CONFIG* saved-dirs *CTR-BLOCK-DIRS*)
     (setq *CTR-FITTING-CONFIG* (ctr-profile-fittings profile))
     (setq *CTR-BLOCK-DIRS* (ctr-profile-block-dirs profile))
     (setq w (nth 5 (car ss)))
     (setq cfg (ctr-get-fitting-config type w))
     (setq stem (if cfg (ctr-cfg-get cfg "BLOCK")))
     (setq blk (ctr-resolve-block-name profile stem))
     (setq *CTR-PENDING-STEM* stem *CTR-PENDING-DIRS* *CTR-BLOCK-DIRS*)
     (cond
       ((null cfg)
        (setq errs (list (list "FITTING_CONFIG_MISSING" pt
                          (strcat type " has no entry for profile " profile ".")))))
       ((or (null stem) (not (apply avail-fn (list blk))))
        (setq errs (list (list "BLOCK_NOT_FOUND" pt
                          (strcat type " block "
                                  (if stem blk "(not configured)")
                                  " not found; fitting not inserted, takeoff 0.")))))
       (T
        (setq tkm (ctr-get-takeoff type w "MAIN")
              tkb (ctr-get-takeoff type w "BRANCH"))
        (setq off (ctr-get-rotation-offset type w))
        (setq rot (+ (ctr-dir-angle (cdr (assoc "ROT" info)))
                     (* off (/ pi 180.0))))
        (setq bo (ctr-get-base-offset type w))
        (setq ins (list (+ (car pt) (- (* (car bo) (cos rot)) (* (cadr bo) (sin rot))))
                        (+ (cadr pt) (+ (* (car bo) (sin rot)) (* (cadr bo) (cos rot))))))
        (setq op (list "FITTING" type blk ins rot nid (ctr-get-scale type w)))))
     (setq *CTR-PENDING-STEM* nil *CTR-PENDING-DIRS* nil)
     (setq *CTR-FITTING-CONFIG* saved-cfg *CTR-BLOCK-DIRS* saved-dirs)))
  (list nid info tkm tkb op errs profile))

;; net = (nodes segs); avail-fn = function (name) -> T if block exists
;; -> (ops errs)
(defun ctr-plan (net avail-fn / nodes segs nps np ops errs s n1 n2 np1 np2
                                d1 d2 p1 p2 tk1 tk2 tr n)
  (setq nodes (car net) segs (cadr net))
  (foreach n nodes
    (setq nps (cons (ctr-plan-node n segs avail-fn) nps)))
  (setq nps (reverse nps))
  (foreach np nps
    (if (nth 4 np) (setq ops (cons (nth 4 np) ops)))
    (setq errs (append errs (nth 5 np))))
  (foreach s segs
    (setq np1 (assoc (nth 1 s) nps) np2 (assoc (nth 2 s) nps))
    (if (or (null (nth 4 s))
            (= (cdr (assoc "TYPE" (nth 1 np1))) "UNSUPPORTED_GEOMETRY")
            (= (cdr (assoc "TYPE" (nth 1 np2))) "UNSUPPORTED_GEOMETRY"))
      (ctr-log "DEBUG" (strcat "segment " (itoa (car s)) " skipped (unsupported geometry)."))
      (progn
        (setq p1 (ctr-node-pt (assoc (nth 1 s) nodes))
              p2 (ctr-node-pt (assoc (nth 2 s) nodes)))
        (setq d1 (ctr-seg-out-dir s (nth 1 s)) d2 (ctr-seg-out-dir s (nth 2 s)))
        (setq tk1 (ctr-arm-takeoff np1 d1) tk2 (ctr-arm-takeoff np2 d2))
        (setq tr (ctr-trim-segment p1 p2 tk1 tk2))
        (if tr
          (setq ops (cons (list "STRAIGHT" (car tr) (cadr tr) (nth 5 s) (car s) (nth 6 s)) ops))
          (setq errs (append errs
                     (list (list "SEGMENT_TOO_SHORT"
                                 (list (/ (+ (car p1) (car p2)) 2.0)
                                       (/ (+ (cadr p1) (cadr p2)) 2.0))
                                 (strcat "length "
                                         (rtos (nth 3 s) 2 3)
                                         " <= takeoffs "
                                         (rtos (+ tk1 tk2) 2 3)
                                         "; straight not generated"))))))))
    )
  (list (reverse ops) errs))

;;; ---------------------------------------------------------------
;;; 8. AUTOCAD LAYER  (requires AutoCAD; entmake / ssget / tblsearch)
;;; ---------------------------------------------------------------
(defun ctr-ensure-layer (name / col tc)
  (if (null (tblsearch "LAYER" name))
    (progn
      (setq col (cdr (assoc name *CTR-LAYER-COLORS*)))
      (setq tc (cdr (assoc name *CTR-LAYER-TRUECOLOR*)))
      (entmake (append
                 (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                       '(100 . "AcDbLayerTableRecord") (cons 2 name) '(70 . 0)
                       (cons 62 (if col col 7)) '(6 . "Continuous"))
                 (if tc (list (cons 420 tc)) nil)))
      (ctr-log "INFO" (strcat "Layer created: " name
                              (if tc (strcat " (true colour " (itoa tc) ")") "")))))
  (if (null (tblsearch "LAYER" name))
    (progn (ctr-log "ERROR" (strcat "LAYER_NOT_AVAILABLE: " name)) nil)
    T))

(defun ctr-ensure-layers ()
  (and (ctr-ensure-layer *CTR-LAYER-PATH*) (ctr-ensure-layer *CTR-LAYER-TRAY*)))

;; Finds <dir>STEM.dwg in DIRS and inserts it under ALIAS ("newname=path"
;; INSERT syntax when ALIAS differs from STEM), then deletes the reference.
;; Real-engine confirmed: when ALIAS already names a block in the drawing,
;; -INSERT silently REDEFINES it from the file with no confirmation prompt --
;; and every existing INSERT of that block updates to the new geometry, same
;; as using BEDIT/Save or "Insert -> Redefine" in the GUI. Returns T/nil.
(defun ctr-insert-block-def (alias stem dirs / f dir last0 last1 src)
  (foreach dir dirs
    (if (and (null f) (findfile (strcat dir stem ".dwg")))
      (setq f (findfile (strcat dir stem ".dwg")))))
  (if f
    (progn
      (setq src (if (= alias stem) f (strcat alias "=" f)))
      (setq last0 (entlast))
      (command "_.-INSERT" src "0,0" "1" "1" "0")
      (setq last1 (entlast))
      (if (and last1 (not (equal last0 last1))) (entdel last1))
      (ctr-log "INFO" (strcat "Block '" alias "' loaded from file: " f)))
    (ctr-log "ERROR" (strcat "BLOCK_NOT_FOUND: " stem
                             ".dwg not found for block '" alias "' in "
                             (ctr-join dirs ", "))))
  (if (tblsearch "BLOCK" alias) T nil))

;; Make sure a block named ALIAS exists in the drawing -- loads it ONCE from
;; file, same name or not (see ctr-insert-block-def). This is what makes the
;; whole planner "just work" the first time a fitting type is used; it does
;; NOT notice if the source .dwg on disk changes afterwards (AutoCAD has no
;; way to know that on its own) -- that's what C:CTRELOAD is for.
(defun ctr-ensure-block (alias stem dirs)
  (if (tblsearch "BLOCK" alias) T (ctr-insert-block-def alias stem dirs)))

;; single-arg wrapper used as the planner's avail-fn: reads the STEM/DIRS that
;; ctr-plan-node stashed in *CTR-PENDING-STEM*/*CTR-PENDING-DIRS* right before
;; this call; falls back to (alias, *CTR-BLOCK-DIRS*) if called with neither
;; pending (keeps old callers/tests working unchanged).
(defun ctr-block-available-p (alias)
  (and alias
       (ctr-ensure-block alias
                         (if *CTR-PENDING-STEM* *CTR-PENDING-STEM* alias)
                         (if *CTR-PENDING-DIRS* *CTR-PENDING-DIRS* *CTR-BLOCK-DIRS*))))

;; read every LWPOLYLINE / LINE on the path layer -> list of (width profile pts).
;; PROFILE is read from a "PROFILE=<name>" 1000-string in the CTR_PATH xdata;
;; a path saved by an older version of this file (no such string) defaults to
;; "DEFAULT" -- this EXTENDS the existing xdata schema, it never breaks a
;; drawing made before profiles existed.
(defun ctr-get-path (/ ss i en ed xd w profile pts item type bulge out s)
  (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE,LINE") (cons 8 *CTR-LAYER-PATH*))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq en (ssname ss i) ed (entget en (list *CTR-APP-PATH*)))
        (setq type (cdr (assoc 0 ed)) w *CTR-DEFAULT-WIDTH* profile "DEFAULT" pts nil bulge nil)
        (setq xd (cdr (assoc -3 ed)))
        (if xd
          (foreach item (cdr (car xd))
            (cond
              ((= (car item) 1040) (setq w (cdr item)))
              ((= (car item) 1000)
               (setq s (cdr item))
               (if (and (>= (strlen s) 8) (= (substr s 1 8) "PROFILE="))
                 (setq profile (substr s 9)))))))
        (foreach item ed
          (cond
            ((and (= type "LWPOLYLINE") (= (car item) 10))
             (setq pts (cons (list (float (cadr item)) (float (caddr item))) pts)))
            ((and (= type "LWPOLYLINE") (= (car item) 42) (/= (cdr item) 0.0))
             (setq bulge T))
            ((and (= type "LINE") (or (= (car item) 10) (= (car item) 11)))
             (setq pts (cons (list (float (cadr item)) (float (caddr item))) pts)))))
        (setq pts (reverse pts))
        (if (and (= type "LWPOLYLINE") (= 1 (logand 1 (cdr (assoc 70 ed)))) pts)
          (setq pts (append pts (list (car pts)))))
        (if bulge
          (ctr-log "ERROR" (strcat "UNSUPPORTED_GEOMETRY: arc segment in path at "
                                   (ctr-fmt-pt (car pts)) "; path skipped."))
          (setq out (cons (list w profile pts) out)))
        (setq i (1+ i)))))
  (reverse out))

;; delete ONLY objects we generated (XDATA CTR_GEN on the tray layer)
(defun ctr-clear-generated (/ ss i n)
  (setq n 0)
  (setq ss (ssget "_X" (list (cons 8 *CTR-LAYER-TRAY*)
                             (list -3 (list *CTR-APP-GEN*)))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (if (entdel (ssname ss i)) (setq n (1+ n)))
        (setq i (1+ i)))))
  (ctr-log "DEBUG" (strcat "CTRAY DEBUG: after-clear object-count=" (itoa (ctr-count-all))
                           " (cleared " (itoa n) " generated)"))
  n)

;; GEOMETRY mode (proven): closed rectangle at +-width/2 either side of the
;; centre line, on layer SCADA-TRAY.
(defun ctr-draw-straight-geometry (p1 p2 width / cs)
  (princ "
ENTERED legacy geometry straight renderer")
  (regapp *CTR-APP-GEN*)
  (setq cs (ctr-straight-corners p1 p2 width))
  (entmake
    (append
      (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 *CTR-LAYER-TRAY*)
            '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1))
      (mapcar '(lambda (p) (cons 10 p)) cs)
      (list (list -3 (list *CTR-APP-GEN* '(1000 . "STRAIGHT")))))))

;; BLOCK mode fallback: insert STRAIGHT_BLOCK with a NON-UNIFORM scale
;; (xscale along the run = segment length / reference length, yscale = width /
;; reference width).  This is the "block reference + scale fallback" the
;; router falls back to instead of guessing a dynamic-block stretch parameter;
;; it WILL distort rung/rail spacing along the length, which is exactly the
;; risk flagged in block_spec_measured.md.  Requires STRAIGHT_BLOCK_REF_LENGTH
;; and STRAIGHT_BLOCK_WIDTH to be confirmed and set on the profile; until then
;; this logs NEEDS_USER_CONFIRMATION once and returns nil so the caller falls
;; back to GEOMETRY mode instead of drawing something wrong.
(defun ctr-draw-straight-block (p1 p2 width profile / prof blk reflen refw ang
                                                     xscale yscale mid rot)
  (setq prof (ctr-get-profile profile))
  (setq blk (if prof (cdr (assoc "STRAIGHT_BLOCK" prof))))
  (setq reflen (if prof (cdr (assoc "STRAIGHT_BLOCK_REF_LENGTH" prof))))
  (setq refw (if prof (cdr (assoc "STRAIGHT_BLOCK_WIDTH" prof))))
  (if (or (null blk) (null reflen) (null refw))
    (progn
      (ctr-warn-once (strcat profile "|STRAIGHT_BLOCK") "WARN"
        (strcat "NEEDS_USER_CONFIRMATION:
profile=" profile
                " STRAIGHT_MODE=BLOCK but STRAIGHT_BLOCK_REF_LENGTH/WIDTH not confirmed.
"
                "Falling back to GEOMETRY rectangle for this run."))
      nil)
    (progn
      (setq *CTR-PENDING-STEM* blk *CTR-PENDING-DIRS* (ctr-profile-block-dirs profile))
      (setq blk (ctr-resolve-block-name profile blk))
      (if (not (ctr-block-available-p blk))
        (progn (setq *CTR-PENDING-STEM* nil *CTR-PENDING-DIRS* nil) nil)
        (progn
          (setq *CTR-PENDING-STEM* nil *CTR-PENDING-DIRS* nil)
          (ctr-warn-once (strcat profile "|STRAIGHT_NONUNIFORM") "WARN"
            (strcat "profile=" profile " straight uses a non-uniform scale fallback"
                    " (length and width scaled independently); rung/rail spacing"
                    " will not match the real fitting until this is confirmed."))
          (setq ang (atan (- (cadr p2) (cadr p1)) (- (car p2) (car p1))))
          (setq xscale (/ (ctr-pt-dist p1 p2) reflen) yscale (/ width refw))
          (setq mid (list (/ (+ (car p1) (car p2)) 2.0) (/ (+ (cadr p1) (cadr p2)) 2.0)))
          (regapp *CTR-APP-GEN*)
          (entmake
            (list '(0 . "INSERT") (cons 8 *CTR-LAYER-TRAY*) (cons 2 blk)
                  (list 10 (car mid) (cadr mid) 0.0)
                  (cons 41 xscale) (cons 42 yscale) (cons 43 1.0) (cons 50 ang)
                  (list -3 (list *CTR-APP-GEN* '(1000 . "STRAIGHT")))))))))) 

;; ---- GENERATED_LADDER: rails + rungs from the real block's own measured
;; authoring geometry (see profile config comment).  Pure entmake, no blocks.
(defun ctr-oriented-rect (ctr ux uy nx ny along-half trans-half)
  (list
    (list (+ (car ctr) (* ux (- along-half)) (* nx trans-half))
          (+ (cadr ctr) (* uy (- along-half)) (* ny trans-half)))
    (list (+ (car ctr) (* ux along-half) (* nx trans-half))
          (+ (cadr ctr) (* uy along-half) (* ny trans-half)))
    (list (+ (car ctr) (* ux along-half) (* nx (- trans-half)))
          (+ (cadr ctr) (* uy along-half) (* ny (- trans-half))))
    (list (+ (car ctr) (* ux (- along-half)) (* nx (- trans-half)))
          (+ (cadr ctr) (* uy (- along-half)) (* ny (- trans-half))))))

;; returns the entmake result (T/entity data on success, nil on failure) so
;; callers can count real successes/failures instead of assuming it worked.
(defun ctr-emit-ladder-rect (corners)
  (regapp *CTR-APP-GEN*)
  (entmake
    (append
      (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 *CTR-LAYER-TRAY*)
            '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1))
      (mapcar '(lambda (p) (cons 10 p)) corners)
      (list (list -3 (list *CTR-APP-GEN* '(1000 . "STRAIGHT")))))))

;; rung centres along the segment: FIRST, FIRST+SPACING, ...
;; CONFIRMED against the real Dynamic Block (user's GUI screenshots, length
;; 1000/1100/1150 all show 4 rungs; 1150 does NOT get a 5th even though
;; 125+4*250+20=1145 <= 1150, which rules out a "never overhang" fit-check).
;; The real rule is simply: rung COUNT = floor(length / spacing), independent
;; of rung width -- a 5th rung only appears once length reaches 1250, not
;; whenever one would merely fit without overhanging.  RW is kept as a
;; parameter (still used to size each rung's geometry) but no longer affects
;; the count.  A small epsilon avoids float round-off flipping an exact
;; multiple of SPACING down by one.
(defun ctr-ladder-rung-centers (length first spacing rw / n k out)
  (setq n (fix (/ (+ length 0.0001) spacing)))
  (setq k 0)
  (while (< k n)
    (setq out (cons (+ first (* (float k) spacing)) out))
    (setq k (1+ k)))
  (reverse out))

(defun ctr-draw-straight-ladder (p1 p2 width profile / prof th rw sp first widths
                                                      len ux uy nx ny centers c ctr ok
                                                      nreq nok nfail firstfail)
  (princ "
ENTERED ctr-draw-straight-ladder")
  (setq prof (ctr-get-profile profile))
  (setq th (if prof (cdr (assoc "STRAIGHT_RAIL_THICKNESS" prof))))
  (setq rw (if prof (cdr (assoc "STRAIGHT_RUNG_WIDTH" prof))))
  (setq sp (if prof (cdr (assoc "STRAIGHT_RUNG_SPACING" prof))))
  (setq first (if prof (cdr (assoc "STRAIGHT_RUNG_FIRST_OFFSET" prof))))
  (setq widths (if prof (cdr (assoc "STRAIGHT_SUPPORTED_WIDTHS" prof))))
  (if (or (null th) (null rw) (null sp) (null first))
    (progn
      (ctr-warn-once (strcat profile "|LADDER_CFG") "WARN"
        (strcat "NEEDS_USER_CONFIRMATION:
profile=" profile
                " STRAIGHT_MODE=GENERATED_LADDER but rail/rung dimensions not"
                " confirmed.
Falling back to GEOMETRY rectangle for this run."))
      nil)
    (progn
      (if (and widths (not (ctr-width-in-list-p width widths)))
        (ctr-warn-once (strcat profile "|LADDER_WIDTH|" (rtos width 2 0)) "WARN"
          (strcat "NEEDS_USER_CONFIRMATION:
width " (rtos width 2 0)
                  " is not one of the block's confirmed presets (150/300/450/600/750)."
                  "
Drawing it anyway at that width; please confirm this is intended.")))
      (ctr-warn-once (strcat profile "|LADDER_TRUNC") "WARN"
        (strcat "NEEDS_USER_CONFIRMATION:
rung truncation at a segment's far end uses a"
                " conservative default (never overhang); not yet confirmed against a real"
                " GUI stretch test."))
      (setq len (ctr-pt-dist p1 p2))
      (setq ux (/ (- (car p2) (car p1)) len) uy (/ (- (cadr p2) (cadr p1)) len))
      (setq nx (- uy) ny ux)
      ;; CONFIRMED (real-engine measurement, see block_spec_measured.md "joint
      ;; delta" section): rail CENTRELINE offset = width/2, matching the SAME
      ;; convention BLOCK_WIDTH-based fittings use (their scaled centreline
      ;; offset comes out to exactly width/2 too) -- NOT width/2-thickness/2
      ;; (that was the old GEOMETRY-mode "outer envelope" convention, which
      ;; measured a real 10.0mm centreline mismatch against the Elbow at
      ;; width=300, confirmed on all 4 turn orientations).
      (setq ctr (list (+ (car p1) (* ux (/ len 2.0)) (* nx (/ width 2.0)))
                      (+ (cadr p1) (* uy (/ len 2.0)) (* ny (/ width 2.0)))))
      (ctr-emit-ladder-rect (ctr-oriented-rect ctr ux uy nx ny (/ len 2.0) (/ th 2.0)))
      (setq ctr (list (+ (car p1) (* ux (/ len 2.0)) (* nx (- (/ width 2.0))))
                      (+ (cadr p1) (* uy (/ len 2.0)) (* ny (- (/ width 2.0))))))
      (ctr-emit-ladder-rect (ctr-oriented-rect ctr ux uy nx ny (/ len 2.0) (/ th 2.0)))
      ;; rungs, spanning between the two rails' INNER edges (centreline -+ (width/2-thickness))
      (setq centers (ctr-ladder-rung-centers len first sp rw))
      (setq nreq (length centers) nok 0 nfail 0 firstfail nil)
      (foreach c centers
        (setq ctr (list (+ (car p1) (* ux c)) (+ (cadr p1) (* uy c))))
        (setq ok (ctr-emit-ladder-rect (ctr-oriented-rect ctr ux uy nx ny (/ rw 2.0)
                                                          (- (/ width 2.0) th))))
        (if ok
          (setq nok (1+ nok))
          (progn
            (setq nfail (1+ nfail))
            (if (null firstfail) (setq firstfail (list c ctr))))))
      (princ (strcat "\nRUNG CREATE requested=" (itoa nreq)
                     " success=" (itoa nok) " failed=" (itoa nfail)))
      (if firstfail
        (princ (strcat "\nRUNG CREATE first failure: centre-dist=" (rtos (car firstfail) 2 3)
                       " world-point=" (ctr-fmt-pt (cadr firstfail))
                       " layer-exists=" (if (tblsearch "LAYER" *CTR-LAYER-TRAY*) "T" "nil"))))
      T)))

;; dispatch on the segment's own profile.  Priority: an insertable BLOCK (if
;; ever confirmed usable), else a measured GENERATED_LADDER, else the plain
;; rectangle -- each falls back to the next when it cannot draw.
(defun ctr-draw-straight (p1 p2 width profile / mode used len rc pf rfirst rsp rrw)
  (setq mode (if profile (ctr-profile-straight-mode profile) "GEOMETRY"))
  (setq len (ctr-pt-dist p1 p2))
  (setq rc 0)
  (if (and (= mode "GENERATED_LADDER") profile (setq pf (ctr-get-profile profile)))
    (progn
      (setq rfirst (cdr (assoc "STRAIGHT_RUNG_FIRST_OFFSET" pf))
            rsp (cdr (assoc "STRAIGHT_RUNG_SPACING" pf))
            rrw (cdr (assoc "STRAIGHT_RUNG_WIDTH" pf)))
      (if (and rfirst rsp rrw)
        (setq rc (length (ctr-ladder-rung-centers len rfirst rsp rrw))))))
  (if *CTR-DEBUG*
    (princ (strcat "\nSTRAIGHT DISPATCH"
                   "\nprofile=" (if profile profile "DEFAULT")
                   "\nmode=" mode
                   "\nstart=" (ctr-fmt-pt p1)
                   "\nend=" (ctr-fmt-pt p2)
                   "\nlength=" (rtos len 2 3)
                   "\nrung_count=" (itoa rc))))
  (setq used
    (cond
      ((and (= mode "BLOCK") (ctr-draw-straight-block p1 p2 width profile)) "ctr-draw-straight-block")
      ((and (= mode "GENERATED_LADDER") (ctr-draw-straight-ladder p1 p2 width profile)) "ctr-draw-straight-ladder")
      ((progn (ctr-draw-straight-geometry p1 p2 width) T) "ctr-draw-straight-geometry")))
  (if *CTR-DEBUG* (princ (strcat "\nrenderer=" used)))
  (ctr-log "DEBUG" (strcat "CTRAY DEBUG: straight profile=" (if profile profile "DEFAULT")
                           " straight_mode=" mode " straight_renderer=" used))
  T)

(defun ctr-make-insert (blk pt rot scale tag)
  (regapp *CTR-APP-GEN*)
  (entmake
    (list '(0 . "INSERT") (cons 8 *CTR-LAYER-TRAY*) (cons 2 blk)
          (list 10 (car pt) (cadr pt) 0.0)
          (cons 41 scale) (cons 42 scale) (cons 43 scale) (cons 50 rot)
          (list -3 (list *CTR-APP-GEN* (cons 1000 tag))))))

;; fitting insertion: block name + insert point + rotation, all resolved by
;; the planner from config; these functions only INSERT.
(defun ctr-insert-elbow (blk pt rot scale) (ctr-make-insert blk pt rot scale "ELBOW"))
(defun ctr-insert-tee   (blk pt rot scale) (ctr-make-insert blk pt rot scale "TEE"))
(defun ctr-insert-cross (blk pt rot scale) (ctr-make-insert blk pt rot scale "CROSS"))

(defun ctr-execute-plan (ops / nS nF op type ok)
  (setq nS 0 nF 0)
  (foreach op ops
    (cond
      ((= (car op) "STRAIGHT")
       (if (ctr-draw-straight (nth 1 op) (nth 2 op) (nth 3 op) (nth 5 op)) (setq nS (1+ nS))
         (ctr-log "ERROR" "ENTMAKE_FAILED: straight")))
      ((= (car op) "FITTING")
       (setq type (nth 1 op))
       (setq ok (cond ((= type "ELBOW") (ctr-insert-elbow (nth 2 op) (nth 3 op) (nth 4 op) (nth 6 op)))
                      ((= type "TEE")   (ctr-insert-tee   (nth 2 op) (nth 3 op) (nth 4 op) (nth 6 op)))
                      ((= type "CROSS") (ctr-insert-cross (nth 2 op) (nth 3 op) (nth 4 op) (nth 6 op)))))
       (if ok (setq nF (1+ nF))
         (ctr-log "ERROR" (strcat "ENTMAKE_FAILED: " type))))))
  (ctr-log "INFO" (strcat "Generated " (itoa nS) " straight(s), " (itoa nF) " fitting(s)."))
  (list nS nF))

(defun ctr-report-errors (errs / e)
  (foreach e errs
    (ctr-log "ERROR" (strcat (car e) " at " (ctr-fmt-pt (cadr e)) ": " (caddr e))))
  (length errs))

;; rebuild everything from the path layer.  Plan first, then clear+draw,
;; so a planning failure never removes the existing result.
(defun ctr-regenerate (/ paths net plan)
  (if (ctr-ensure-layers)
    (progn
      (setq paths (ctr-get-path))
      (if (null paths)
        (ctr-log "WARN" (strcat "No path objects on layer " *CTR-LAYER-PATH* "."))
        (progn
          (setq net (ctr-build-network paths))
          (setq plan (ctr-plan net 'ctr-block-available-p))
          (ctr-report-errors (cadr plan))
          (ctr-clear-generated)
          (ctr-execute-plan (car plan))))))
  (princ))

;;; ---------------------------------------------------------------
;;; 9. COMMANDS (single Undo group, ESC safe)
;;; ---------------------------------------------------------------
(setq *CTR-UNDO-OPEN* nil)
(setq *CTR-OLD-ORTHO* nil)

(defun ctr-end ()
  (if *CTR-UNDO-OPEN*
    (progn (command "_.UNDO" "_END") (setq *CTR-UNDO-OPEN* nil)))
  (if *CTR-OLD-CMDECHO* (setvar "CMDECHO" *CTR-OLD-CMDECHO*))
  (if *CTR-OLD-ORTHO* (progn (setvar "ORTHOMODE" *CTR-OLD-ORTHO*) (setq *CTR-OLD-ORTHO* nil)))
  (setq *error* *CTR-OLD-ERROR*)
  (princ))

(defun ctr-on-error (msg)
  (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*EXIT*")))
    (ctr-log "ERROR" (strcat "Unexpected error: " msg)))
  (ctr-end))

(defun ctr-begin ()
  (setq *CTR-OLD-ERROR* *error*)
  (setq *CTR-OLD-CMDECHO* (getvar "CMDECHO"))
  (setq *CTR-OLD-ORTHO* (getvar "ORTHOMODE"))
  (setvar "ORTHOMODE" 1)                       ; freehand picks become orthogonal
  (setq *error* ctr-on-error)
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BEGIN")
  (setq *CTR-UNDO-OPEN* T))

;; Uses getstring + manual matching, NOT getkword/initget: real-engine testing
;; found getkword rejects EVERY keyword answer fed through a script in this
;; accoreconsole build -- even AutoCAD's own textbook "Yes/No" example fails
;; the identical way ("Invalid option keyword") -- so this sidesteps AutoCAD's
;; keyword-matching subsystem entirely instead of depending on it working.
;; Case-insensitive; blank input keeps the current profile.
(defun ctr-ask-profile (/ names ans hit n)
  (setq *CTR-PREV-PROFILE* *CTR-CURRENT-PROFILE*)
  (setq names (ctr-profile-names))
  (setq ans (getstring (strcat "
Cable Tray profile [" (ctr-join names "/")
                               "] <" *CTR-CURRENT-PROFILE* ">: ")))
  (setq *CTR-LAST-PROFILE-ANSWER* (if (or (null ans) (= ans "")) "(blank -> kept current)" ans))
  (cond
    ((or (null ans) (= ans "")) nil)
    (T
     (setq hit nil)
     (foreach n names (if (= (strcase n) (strcase ans)) (setq hit n)))
     (if hit
       (setq *CTR-CURRENT-PROFILE* hit)
       (ctr-log "ERROR" (strcat "UNKNOWN_PROFILE: '" ans "' is not one of ["
                                (ctr-join names "/") "]; keeping "
                                *CTR-CURRENT-PROFILE* ".")))))
  *CTR-CURRENT-PROFILE*)

;; Reads/writes *CTR-CURRENT-WIDTH* directly (the same variable CT/CTSET use),
;; so a width typed here is immediately what CT uses next, no separate memory.
(defun ctr-ask-width (/ w)
  (initget 6)
  (setq w (getreal (strcat "\nCable Tray Width <" (rtos *CTR-CURRENT-WIDTH* 2 0) ">: ")))
  (if w (setq *CTR-CURRENT-WIDTH* w))
  *CTR-CURRENT-WIDTH*)

(defun ctr-count-layer (layer / ss) (setq ss (ssget "_X" (list (cons 8 layer)))) (if ss (sslength ss) 0))
(defun ctr-count-all (/ ss) (setq ss (ssget "_X")) (if ss (sslength ss) 0))

;; create the centre-line path; returns its ename, or nil (and logs) on failure.
;; PROFILE is stored as a "PROFILE=<name>" 1000-string alongside the existing
;; "PATH" tag and 1040 width, so CTRAYUPDATE can rebuild each path with its OWN
;; profile later, instead of the session's current one (see ctr-get-path).
(defun ctr-make-path (pts width profile / p ok en0 en1)
  (regapp *CTR-APP-PATH*)
  (setq en0 (entlast))
  (setq ok
    (entmake
      (append
        (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 *CTR-LAYER-PATH*)
              '(100 . "AcDbPolyline") (cons 90 (length pts)) '(70 . 0))
        (mapcar '(lambda (p) (cons 10 p)) pts)
        (list (list -3 (list *CTR-APP-PATH* '(1000 . "PATH") (cons 1040 width)
                             (cons 1000 (strcat "PROFILE=" profile))))))))
  (setq en1 (entlast))
  (if (and ok en1 (not (equal en0 en1)))
    en1
    (progn (ctr-log "ERROR" "CTRAY ERROR: PATH_ENTMAKE_FAILED") nil)))

;; Shared body for C:CTRAY (asks Profile + Width every time -- debug/advanced)
;; and C:CT (day-to-day: uses *CTR-CURRENT-PROFILE*/*CTR-CURRENT-WIDTH* as-is,
;; set once via CTSET, no prompts).  ASK? = T -> CTRAY behaviour, nil -> CT.
(defun ctr-do-ctray (ask? / profile w p0 pts prev nxt snap en)
  (ctr-begin)
  (if (ctr-ensure-layers)
    (progn
      (if *CTR-DEBUG*
        (progn
          (princ (strcat "\nCTRAY VERSION=" *CTR-VERSION*))
          (princ (strcat "\nCTRAY SOURCE=" *CTR-SOURCE-ID*))))
      (if ask?
        (progn
          (if *CTR-DEBUG* (princ (strcat "\nCTRAY PREVIOUS CURRENT PROFILE=" *CTR-CURRENT-PROFILE*)))
          (setq profile (ctr-ask-profile))
          (if *CTR-DEBUG*
            (progn
              (princ (strcat "\nCTRAY USER INPUT=" *CTR-LAST-PROFILE-ANSWER*))
              (princ (strcat "\nCTRAY RESOLVED PROFILE=" profile))
              (princ (strcat "\nCTRAY NEW CURRENT PROFILE=" *CTR-CURRENT-PROFILE*))))
          (setq w (ctr-ask-width)))
        (progn
          (setq profile *CTR-CURRENT-PROFILE* w *CTR-CURRENT-WIDTH*)
          (princ (strcat "\nCable Tray: " profile " / " (rtos w 2 0) "mm"))))
      (ctr-log "DEBUG" (strcat "CTRAY DEBUG: profile=" profile))
      (setq p0 (getpoint "
Specify start point: "))
      (if p0
        (progn
          (setq prev (ctr-2d p0) pts (list prev))
          (while (setq nxt (getpoint (list (car prev) (cadr prev) 0.0)
                                     "
Specify next point or <Enter to finish>: "))
            (setq nxt (ctr-2d nxt))
            (setq snap (ctr-snap-ortho prev nxt))
            (if (> (ctr-pt-dist snap nxt) *CTR-TOL*)
              (ctr-log "INFO" (strcat "point " (ctr-fmt-pt nxt) " snapped to orthogonal "
                                      (ctr-fmt-pt snap))))
            (setq nxt snap)
            (cond
              ((< (ctr-pt-dist prev nxt) *CTR-TOL*)
               (ctr-log "WARN" "ZERO_LENGTH: point equals previous point; ignored."))
              ((null (ctr-direction prev nxt))
               (ctr-log "ERROR" (strcat "UNSUPPORTED_GEOMETRY: segment "
                                        (ctr-fmt-pt prev) " -> " (ctr-fmt-pt nxt)
                                        " is not 0/90/180/270; point rejected.")))
              (T (setq pts (append pts (list nxt)) prev nxt))))
          (ctr-log "DEBUG" (strcat "CTRAY DEBUG: points=" (itoa (length pts))))
          (if (< (length pts) 2)
            (ctr-log "ERROR" "PATH_TOO_SHORT: need at least 2 points; nothing created.")
            (progn
              (ctr-log "DEBUG" "CTRAY DEBUG: creating-path")
              (setq en (ctr-make-path pts w profile))
              (ctr-log "DEBUG" (strcat "CTRAY DEBUG: path-entity=" (if en (strcat "handle " (cdr (assoc 5 (entget en)))) "nil")))
              (if en
                (progn
                  (ctr-log "DEBUG" (strcat "CTRAY DEBUG: before-regenerate object-count=" (itoa (ctr-count-all))))
                  (ctr-regenerate)
                  (ctr-log "DEBUG" (strcat "CTRAY DEBUG: after-regenerate object-count=" (itoa (ctr-count-all))
                                           "  path-objects=" (itoa (ctr-count-layer *CTR-LAYER-PATH*))))))))))))
  (ctr-end))

;; CTRAY: debug/advanced -- always asks Profile + Width.
(defun c:CTRAY () (ctr-do-ctray T))

;; CT: day-to-day -- no prompts, uses whatever CTSET last set (or the
;; session's first-load default, SCADA_BASIC/300).
(defun c:CT () (ctr-do-ctray nil))

(defun c:CTRAYUPDATE ()
  (ctr-begin)
  (ctr-regenerate)
  (ctr-end))

;; CTU: short alias for CTRAYUPDATE, same function, no duplicated logic.
(defun c:CTU () (c:CTRAYUPDATE))

;; CTSET: the ONLY place Profile/Width get asked for day-to-day use. Updates
;; *CTR-CURRENT-PROFILE*/*CTR-CURRENT-WIDTH* immediately (no APPLOAD needed);
;; CT picks up the new values on its very next run, this session.
(defun c:CTSET ()
  (princ (strcat "\nCurrent profile: " *CTR-CURRENT-PROFILE*))
  (princ (strcat "\nCurrent width: " (rtos *CTR-CURRENT-WIDTH* 2 0)))
  (ctr-ask-profile)
  (ctr-ask-width)
  (princ (strcat "\nCable Tray: " *CTR-CURRENT-PROFILE* " / " (rtos *CTR-CURRENT-WIDTH* 2 0) "mm"))
  (princ))

;; CTDEBUG: toggles *CTR-DEBUG* (OFF by default). ON shows CTRAY VERSION/SOURCE,
;; STRAIGHT DISPATCH, ENTERED .../RUNG CREATE/renderer=, and object-count lines;
;; WARN/ERROR (NEEDS_USER_CONFIRMATION etc.) always show regardless.
(defun c:CTDEBUG ()
  (setq *CTR-DEBUG* (not *CTR-DEBUG*))
  (princ (strcat "\nCable Tray debug: " (if *CTR-DEBUG* "ON" "OFF")))
  (princ))

;; Forces every one of PROFILE's configured block names (Elbow/Tee/Cross +
;; the Straight block, whichever exist in its config) to be re-read from
;; their source .dwg RIGHT NOW, even if a same-named block is already
;; defined in this drawing.  Existing inserts of that block update to the
;; new geometry automatically (standard AutoCAD block-redefine behaviour --
;; confirmed on this engine: -INSERT alias=path silently redefines, no
;; prompt).  Use this after editing a source block file (e.g. D:\BLOCK\...)
;; and re-running CT/CTU in a drawing that already used that block once --
;; otherwise the stale in-drawing definition keeps being reused forever,
;; because AutoCAD has no way to notice the file on disk changed.
(defun ctr-reload-profile-blocks (profile / prof dirs fits e stem alias sb n)
  (setq prof (ctr-get-profile profile))
  (setq dirs (ctr-profile-block-dirs profile))
  (setq fits (ctr-profile-fittings profile))
  (setq n 0)
  (foreach e fits
    (setq stem (ctr-cfg-get e "BLOCK"))
    (if stem
      (progn
        (setq alias (ctr-resolve-block-name profile stem))
        (if (ctr-insert-block-def alias stem dirs) (setq n (1+ n))))))
  (if prof
    (progn
      (setq sb (cdr (assoc "STRAIGHT_BLOCK" prof)))
      (if sb
        (progn
          (setq alias (ctr-resolve-block-name profile sb))
          (if (ctr-insert-block-def alias sb dirs) (setq n (1+ n)))))))
  n)

(defun c:CTRELOAD (/ n)
  (setq n (ctr-reload-profile-blocks *CTR-CURRENT-PROFILE*))
  (princ (strcat "\nCable Tray: reloaded " (itoa n) " block(s) for profile "
                 *CTR-CURRENT-PROFILE* " from disk. Run CTU to refresh the drawing."))
  (princ))

;; CTINSPECT: read-only.  Rebuilds the network from SCADA-TRAY-PATH (same
;; ctr-get-path/ctr-build-network/ctr-classify-node the real planner uses --
;; not a separate check) and prints every node's coordinate, degree and
;; classification, so a "why is this a Cross, not a Tee" question can be
;; answered by looking at the actual topology instead of a screenshot. Draws
;; and modifies nothing.
(defun c:CTINSPECT (/ paths net nodes segs n info dirs line)
  (if (ctr-ensure-layers)
    (progn
      (setq paths (ctr-get-path))
      (if (null paths)
        (princ (strcat "\nNo path objects on layer " *CTR-LAYER-PATH* "."))
        (progn
          (setq net (ctr-build-network paths))
          (setq nodes (car net) segs (cadr net))
          (princ (strcat "\nCTINSPECT: " (itoa (length nodes)) " node(s), "
                         (itoa (length segs)) " segment(s)"))
          (foreach n nodes
            (setq info (ctr-classify-node (car n) segs))
            (setq dirs (cdr (assoc "DIRS" info)))
            (setq line (strcat "\n  node " (ctr-fmt-pt (ctr-node-pt n))
                               "  degree=" (itoa (cdr (assoc "DEGREE" info)))
                               "  type=" (cdr (assoc "TYPE" info))))
            (if dirs (setq line (strcat line "  dirs=[" (ctr-join (mapcar 'ctr-dir-name dirs) ",") "]")))
            (if (assoc "MAIN" info) (setq line (strcat line "  main=[" (ctr-join (mapcar 'ctr-dir-name (cdr (assoc "MAIN" info))) ",") "]")))
            (if (assoc "BRANCH" info) (setq line (strcat line "  branch=" (ctr-dir-name (cdr (assoc "BRANCH" info))))))
            (if (assoc "REASON" info) (setq line (strcat line "  reason=" (cdr (assoc "REASON" info)))))
            (princ line))))))
  (princ))

(princ (strcat "\ncable_tray_router " *CTR-VERSION*
               " loaded.  Commands: CT, CTU, CTSET, CTDEBUG, CTINSPECT, CTRELOAD  (advanced: CTRAY, CTRAYUPDATE)"))
(princ)
