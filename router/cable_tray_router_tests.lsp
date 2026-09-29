;;; ====================================================================
;;; cable_tray_router_tests.lsp -- unit tests for sections 1-7 of
;;; cable_tray_router.lsp (pure algorithm, no AutoCAD objects created).
;;;
;;; In AutoCAD :  (load "cable_tray_router.lsp") (load "cable_tray_router_tests.lsp")
;;;               (ctr-run-tests)
;;; Headless   :  python tools/run_tests.py   (uses tools/lisp_sim.py)
;;; ====================================================================
(setq *T-PASS* 0 *T-FAIL* 0)

(defun t-check (name ok)
  (if ok
    (setq *T-PASS* (1+ *T-PASS*))
    (setq *T-FAIL* (1+ *T-FAIL*)))
  (princ (strcat "\n  " (if ok "PASS  " "FAIL  ") name))
  ok)

(defun t-near (a b) (< (abs (- a b)) 0.000001))
(defun t-pt-near (p q) (and (t-near (car p) (car q)) (t-near (cadr p) (cadr q))))
(defun t-avail (n) T)
(defun t-none (n) nil)
(defun t-plan (paths) (ctr-plan (ctr-build-network paths) 't-avail))

(defun t-count (ops kind / n o)
  (setq n 0)
  (foreach o ops (if (= (car o) kind) (setq n (1+ n))))
  n)
(defun t-count-fit (ops type / n o)
  (setq n 0)
  (foreach o ops (if (and (= (car o) "FITTING") (= (nth 1 o) type)) (setq n (1+ n))))
  n)
(defun t-ops (plan kind / out o)
  (foreach o (car plan) (if (= (car o) kind) (setq out (cons o out))))
  (reverse out))
(defun t-node-info (net pt)
  (ctr-classify-node (ctr-find-node (car net) pt) (cadr net)))
(defun t-type (net pt) (cdr (assoc "TYPE" (t-node-info net pt))))
(defun t-log-has (text / hit l)
  (foreach l *CTR-LOG* (if (wcmatch-lite l text) (setq hit T)))
  hit)
;; tiny substring test (no wcmatch so it also runs in the simulator)
(defun wcmatch-lite (s sub / i n m hit)
  (setq n (strlen s) m (strlen sub) i 1)
  (while (and (not hit) (<= (+ i m -1) n))
    (if (= (substr s i m) sub) (setq hit T))
    (setq i (1+ i)))
  hit)
(defun t-reset () (setq *CTR-WARNED* nil *CTR-LOG* nil))

(defun t-config (tk rot bo / bw)
  (setq bw 300.0)
  (list
    (list (cons "TYPE" "ELBOW") (cons "BLOCK" "B_ELBOW") (cons "WIDTH" nil)
          (cons "BLOCK_WIDTH" bw) (cons "TAKEOFF" tk) (cons "BRANCH_TAKEOFF" nil)
          (cons "ROTATION_OFFSET" rot) (cons "BASE_OFFSET" (car (list bo))))
    (list (cons "TYPE" "TEE") (cons "BLOCK" "B_TEE") (cons "WIDTH" nil)
          (cons "BLOCK_WIDTH" bw) (cons "TAKEOFF" tk) (cons "BRANCH_TAKEOFF" nil)
          (cons "ROTATION_OFFSET" rot) (cons "BASE_OFFSET" (car (list bo))))
    (list (cons "TYPE" "CROSS") (cons "BLOCK" "B_CROSS") (cons "WIDTH" nil)
          (cons "BLOCK_WIDTH" bw) (cons "TAKEOFF" tk) (cons "BRANCH_TAKEOFF" nil)
          (cons "ROTATION_OFFSET" rot) (cons "BASE_OFFSET" (car (list bo))))))

;; ------------------------------------------------------------------
(defun ctr-run-tests (/ saved-cfg net plan p1 p2 info ops st cfg o in-op out-op)
  (setq *T-PASS* 0 *T-FAIL* 0 *CTR-QUIET* T)
  (setq saved-cfg *CTR-FITTING-CONFIG*)
  (setq *CTR-FITTING-CONFIG* (t-config 0.0 0.0 nil))   ; neutral config for T00-T07

  (princ "\nT00 network model  A-B-C-D")
  (t-reset)
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 -2000.0) (6000.0 -2000.0))))))
  (t-check "4 nodes" (= 4 (length (car net))))
  (t-check "3 segments AB BC CD" (= 3 (length (cadr net))))
  (t-check "degrees A1 B2 C2 D1"
    (equal (mapcar '(lambda (n) (ctr-node-degree (car n) (cadr net))) (car net)) '(1 2 2 1)))
  (t-check "segment length/dir/width AB"
    (and (t-near 3000.0 (nth 3 (car (cadr net)))) (= 0 (nth 4 (car (cadr net))))
         (t-near 300.0 (nth 5 (car (cadr net))))))
  (t-check "BC direction is South(3)" (= 3 (nth 4 (cadr (cadr net)))))

  (princ "\nT01 straight  A---B")
  (t-reset)
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (3000.0 0.0))))))
  (setq plan (ctr-plan net 't-avail))
  (t-check "both nodes END" (and (= "END" (t-type net '(0.0 0.0))) (= "END" (t-type net '(3000.0 0.0)))))
  (t-check "degree 1 / 1" (and (= 1 (ctr-node-degree 0 (cadr net))) (= 1 (ctr-node-degree 1 (cadr net)))))
  (t-check "1 straight, 0 fittings, 0 errors"
    (and (= 1 (t-count (car plan) "STRAIGHT")) (= 0 (t-count (car plan) "FITTING")) (null (cadr plan))))

  (princ "\nT02 elbow  A---B / C")
  (t-reset)
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 2000.0))))))
  (setq plan (ctr-plan net 't-avail))
  (t-check "middle node = ELBOW" (= "ELBOW" (t-type net '(3000.0 0.0))))
  (t-check "2 straights + 1 elbow" (and (= 2 (t-count (car plan) "STRAIGHT")) (= 1 (t-count-fit (car plan) "ELBOW"))))
  (t-check "elbow arms West+North -> rotation 90 deg"
    (t-near (/ pi 2.0) (nth 4 (car (t-ops plan "FITTING")))))
  (t-check "elbow rotation table E+N=0 N+W=1 W+S=2 S+E=3 (both orders)"
    (and (= 0 (ctr-elbow-rotation 0 1)) (= 0 (ctr-elbow-rotation 1 0))
         (= 1 (ctr-elbow-rotation 1 2)) (= 1 (ctr-elbow-rotation 2 1))
         (= 2 (ctr-elbow-rotation 2 3)) (= 2 (ctr-elbow-rotation 3 2))
         (= 3 (ctr-elbow-rotation 3 0)) (= 3 (ctr-elbow-rotation 0 3))))
  (t-check "elbow rejects non-adjacent dirs" (null (ctr-elbow-rotation 0 2)))

  (princ "\nT03 tee  A---B---C / D")
  (t-reset)
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (3000.0 0.0) (6000.0 0.0)))
                                 (300.0 ((3000.0 2000.0) (3000.0 0.0))))))
  (setq plan (ctr-plan net 't-avail))
  (setq info (t-node-info net '(3000.0 0.0)))
  (t-check "B degree 3, TYPE TEE"
    (and (= 3 (ctr-node-degree (ctr-find-node (car net) '(3000.0 0.0)) (cadr net)))
         (= "TEE" (cdr (assoc "TYPE" info)))))
  (t-check "Main = East/West (0 2), Branch = North (1)"
    (and (equal (cdr (assoc "MAIN" info)) '(0 2)) (= 1 (cdr (assoc "BRANCH" info)))))
  (t-check "3 straights + 1 tee, rotation 0"
    (and (= 3 (t-count (car plan) "STRAIGHT")) (= 1 (t-count-fit (car plan) "TEE"))
         (t-near 0.0 (nth 4 (car (t-ops plan "FITTING"))))))
  (t-check "tee rotation table branch N/W/S/E = 0/1/2/3"
    (and (= 0 (ctr-tee-rotation 1)) (= 1 (ctr-tee-rotation 2))
         (= 2 (ctr-tee-rotation 3)) (= 3 (ctr-tee-rotation 0))))
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (3000.0 0.0) (6000.0 0.0)))
                                 (300.0 ((3000.0 -2000.0) (3000.0 0.0))))))
  (setq info (t-node-info net '(3000.0 0.0)))
  (t-check "branch South -> ROT 2" (and (= 3 (cdr (assoc "BRANCH" info))) (= 2 (cdr (assoc "ROT" info)))))
  (setq net (ctr-build-network '((300.0 ((3000.0 -3000.0) (3000.0 0.0) (3000.0 3000.0)))
                                 (300.0 ((6000.0 0.0) (3000.0 0.0))))))
  (setq info (t-node-info net '(3000.0 0.0)))
  (t-check "vertical main, branch East -> main (1 3), ROT 3"
    (and (equal (cdr (assoc "MAIN" info)) '(1 3)) (= 0 (cdr (assoc "BRANCH" info)))
         (= 3 (cdr (assoc "ROT" info)))))

  (princ "\nT04 cross")
  (t-reset)
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (3000.0 0.0) (6000.0 0.0)))
                                 (300.0 ((3000.0 2000.0) (3000.0 0.0) (3000.0 -2000.0))))))
  (setq plan (ctr-plan net 't-avail))
  (t-check "centre degree 4, CROSS" (= "CROSS" (t-type net '(3000.0 0.0))))
  (t-check "4 straights + 1 cross" (and (= 4 (t-count (car plan) "STRAIGHT")) (= 1 (t-count-fit (car plan) "CROSS"))))

  (princ "\nT05 multi-bend")
  (t-reset)
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 -2000.0) (6000.0 -2000.0))))))
  (t-check "S E S E S : 3 straights, 2 elbows" (and (= 3 (t-count (car plan) "STRAIGHT")) (= 2 (t-count-fit (car plan) "ELBOW"))))
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 -2000.0) (6000.0 -2000.0) (6000.0 -4000.0))))))
  (t-check "A-B|C-D|E : 4 straights, 3 elbows" (and (= 4 (t-count (car plan) "STRAIGHT")) (= 3 (t-count-fit (car plan) "ELBOW"))))
  (setq ops (t-ops plan "FITTING"))
  (t-check "elbow quarter-turns B(W+S)=2, C(N+E)=0, D(W+S)=2"
    (equal (mapcar '(lambda (o) (fix (+ 0.5 (/ (nth 4 o) (/ pi 2.0))))) ops) '(2 0 2)))

  (princ "\nT06 unsupported geometry")
  (t-reset)
  (setq plan (t-plan '((300.0 ((0.0 0.0) (1000.0 1000.0))))))
  (t-check "no ops generated" (null (car plan)))
  (t-check "2 UNSUPPORTED_GEOMETRY errors with coordinates"
    (and (= 2 (length (cadr plan)))
         (= "UNSUPPORTED_GEOMETRY" (car (car (cadr plan))))
         (t-pt-near '(0.0 0.0) (cadr (car (cadr plan))))
         (t-pt-near '(1000.0 1000.0) (cadr (cadr (cadr plan))))))
  (t-check "tolerance: 0.1 over 3000 still orthogonal, 3 over 3000 is not"
    (and (= 0 (ctr-direction '(0.0 0.0) '(3000.0 0.1))) (null (ctr-direction '(0.0 0.0) '(3000.0 3.0)))))
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 2000.0))) (300.0 ((3000.0 0.0) (4000.0 1000.0))))))
  (t-check "one diagonal at a bend: nothing touching that node is generated"
    (and (= 0 (t-count-fit (car plan) "TEE")) (= 0 (t-count-fit (car plan) "ELBOW"))))
  (setq plan (t-plan '((300.0 ((0.0 0.0) (1000.0 0.0))) (300.0 ((0.0 0.0) (0.0 1000.0)))
                       (300.0 ((0.0 0.0) (-1000.0 0.0))) (300.0 ((0.0 0.0) (0.0 -1000.0)))
                       (300.0 ((0.0 0.0) (1000.0 1000.0))))))
  (t-check "5 segments at a node -> MORE_THAN_4_SEGMENTS"
    (t-log-has-err (cadr plan) "MORE_THAN_4_SEGMENTS"))

  (princ "\nT07 straight geometry (horizontal + vertical + reversed)")
  (setq cfg (ctr-straight-corners '(0.0 0.0) '(3000.0 0.0) 300.0))
  (t-check "horizontal WIDTH 300 -> y = +150 / -150"
    (and (t-pt-near (nth 0 cfg) '(0.0 150.0)) (t-pt-near (nth 1 cfg) '(3000.0 150.0))
         (t-pt-near (nth 2 cfg) '(3000.0 -150.0)) (t-pt-near (nth 3 cfg) '(0.0 -150.0))))
  (setq cfg (ctr-straight-corners '(0.0 0.0) '(0.0 2000.0) 300.0))
  (t-check "vertical WIDTH 300 -> x = -150 / +150"
    (and (t-pt-near (nth 0 cfg) '(-150.0 0.0)) (t-pt-near (nth 1 cfg) '(-150.0 2000.0))
         (t-pt-near (nth 2 cfg) '(150.0 2000.0)) (t-pt-near (nth 3 cfg) '(150.0 0.0))))
  (setq cfg (ctr-straight-corners '(3000.0 0.0) '(0.0 0.0) 300))
  (t-check "reversed direction + integer width still correct (half width 150)"
    (and (t-near 150.0 (abs (cadr (nth 0 cfg)))) (t-near 150.0 (abs (cadr (nth 3 cfg))))
         (t-near 300.0 (ctr-pt-dist (nth 0 cfg) (nth 3 cfg)))))

  (princ "\nT08 takeoff (config TAKEOFF = 300)")
  (setq *CTR-FITTING-CONFIG* (t-config 300.0 nil nil))
  (t-reset)
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 2000.0))))))
  (setq ops (t-ops plan "STRAIGHT"))
  (t-check "AB trimmed to (0,0)-(2700,0)"
    (and (t-pt-near (nth 1 (car ops)) '(0.0 0.0)) (t-pt-near (nth 2 (car ops)) '(2700.0 0.0))))
  (t-check "BC trimmed to (3000,300)-(3000,2000)"
    (and (t-pt-near (nth 1 (cadr ops)) '(3000.0 300.0)) (t-pt-near (nth 2 (cadr ops)) '(3000.0 2000.0))))
  (t-check "trim formula: length - tk1 - tk2"
    (t-near 1700.0 (ctr-pt-dist '(3000.0 300.0) '(3000.0 2000.0))))
  (t-check "no NEEDS_USER_CONFIRMATION for takeoff when configured"
    (not (t-log-has "TAKEOFF not configured")))

  (princ "\nT09 segment too short")
  (t-reset)
  (setq plan (t-plan '((300.0 ((0.0 0.0) (500.0 0.0) (500.0 500.0) (1000.0 500.0))))))
  (t-check "middle 500 segment between two elbows (300+300) -> SEGMENT_TOO_SHORT"
    (t-log-has-err (cadr plan) "SEGMENT_TOO_SHORT"))
  (t-check "no reversed/negative straight: 2 straights (200 long) + 2 elbows"
    (and (= 2 (t-count (car plan) "STRAIGHT")) (= 2 (t-count-fit (car plan) "ELBOW"))))
  (t-check "trim returns nil when takeoffs >= length" (null (ctr-trim-segment '(0.0 0.0) '(500.0 0.0) 300.0 300.0)))

  (princ "\nT10 rotation offset + base offset")
  (setq *CTR-FITTING-CONFIG* (t-config 0.0 90.0 '(10.0 0.0)))
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 2000.0))))))
  (setq ops (t-ops plan "FITTING"))
  (t-check "rot = 90 (geometry) + 90 (offset) = 180"
    (t-near pi (nth 4 (car ops))))
  (t-check "insert = node + rot180((10,0)) = (2990,0)"
    (t-pt-near (nth 3 (car ops)) '(2990.0 0.0)))

  (princ "\nT11 unknown config -> NEEDS_USER_CONFIRMATION, fallback 0, no crash")
  (setq *CTR-FITTING-CONFIG* (t-config nil nil nil))
  (t-reset)
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 2000.0))))))
  (t-check "log says ELBOW TAKEOFF not configured" (t-log-has "ELBOW TAKEOFF not configured."))
  (t-check "log says Temporary test value = 0" (t-log-has "Temporary test value = 0."))
  (t-check "straights untrimmed" (t-pt-near (nth 2 (car (t-ops plan "STRAIGHT"))) '(3000.0 0.0)))
  (t-check "warned once only" (= 1 (t-count-log "ELBOW TAKEOFF not configured")))

  (princ "\nT12 block missing / config missing")
  (setq *CTR-FITTING-CONFIG* (t-config 300.0 0.0 nil))
  (t-reset)
  (setq plan (ctr-plan (ctr-build-network '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 2000.0))))) 't-none))
  (t-check "BLOCK_NOT_FOUND reported, no fitting" (and (t-log-has-err (cadr plan) "BLOCK_NOT_FOUND") (= 0 (t-count (car plan) "FITTING"))))
  (t-check "straights NOT trimmed when fitting cannot be inserted"
    (t-pt-near (nth 2 (car (t-ops plan "STRAIGHT"))) '(3000.0 0.0)))
  (setq *CTR-FITTING-CONFIG* nil)
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 2000.0))))))
  (t-check "empty config -> FITTING_CONFIG_MISSING" (t-log-has-err (cadr plan) "FITTING_CONFIG_MISSING"))
  (setq *CTR-FITTING-CONFIG* saved-cfg)

  (princ "\nT13 CTRAYUPDATE scenarios (T-junction / crossing / re-classify)")
  (t-reset)
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 -2000.0))))))
  (t-check "before: corner is ELBOW" (= "ELBOW" (t-type net '(3000.0 0.0))))
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 -2000.0)))
                                 (300.0 ((3000.0 0.0) (6000.0 0.0))))))
  (t-check "after adding branch: same node re-classified TEE" (= "TEE" (t-type net '(3000.0 0.0))))
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (6000.0 0.0))) (300.0 ((3000.0 2000.0) (3000.0 0.0))))))
  (t-check "branch ending mid-span splits the run -> TEE, 3 segments" (and (= "TEE" (t-type net '(3000.0 0.0))) (= 3 (length (cadr net)))))
  (setq plan (ctr-plan (ctr-build-network '((300.0 ((0.0 0.0) (6000.0 0.0))) (300.0 ((3000.0 -2000.0) (3000.0 2000.0))))) 't-avail))
  (t-check "two lines crossing mid-span -> CROSS, 4 straights" (and (= 1 (t-count-fit (car plan) "CROSS")) (= 4 (t-count (car plan) "STRAIGHT"))))
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0))) (300.0 ((0.0 0.0) (1000.0 0.0))))))
  (t-check "overlapping duplicate segment collapses (2 straights, no error)" (and (= 2 (t-count (car plan) "STRAIGHT")) (null (cadr plan))))

  (princ "\nT14 input errors")
  (t-reset)
  (setq net (ctr-build-network '((300.0 ((0.0 0.0))))))
  (t-check "single point path: no segments, PATH_TOO_SHORT logged" (and (null (cadr net)) (t-log-has "PATH_TOO_SHORT")))
  (t-reset)
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (0.0 0.0))))))
  (t-check "two coincident points: no segment, ZERO_LENGTH logged" (and (null (cadr net)) (t-log-has "ZERO_LENGTH")))
  (setq net (ctr-build-network '((300.0 ((0.0 0.0) (0.0 0.0) (1000.0 0.0))))))
  (t-check "duplicate point inside path ignored, 1 segment" (= 1 (length (cadr net))))
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0))) (200.0 ((3000.0 0.0) (3000.0 2000.0))))))
  (t-check "width change at a bend -> UNSUPPORTED (no reducer), no fitting"
    (and (t-log-has-err (cadr plan) "WIDTH_MISMATCH") (= 0 (t-count (car plan) "FITTING"))))

  (princ "\nT15 angle engine")
  (t-check "normalize -pi/2 = 3pi/2" (t-near (* 1.5 pi) (ctr-angle-normalize (- (/ pi 2.0)))))
  (t-check "normalize 5pi = pi" (t-near pi (ctr-angle-normalize (* 5.0 pi))))
  (t-check "normalize 2pi = 0" (t-near 0.0 (ctr-angle-normalize (* 2.0 pi))))
  (t-check "directions E N W S"
    (equal (list (ctr-direction '(0.0 0.0) '(5.0 0.0)) (ctr-direction '(0.0 0.0) '(0.0 5.0))
                 (ctr-direction '(0.0 0.0) '(-5.0 0.0)) (ctr-direction '(0.0 0.0) '(0.0 -5.0)))
           '(0 1 2 3)))
  (t-check "zero-length direction = nil" (null (ctr-direction '(1.0 1.0) '(1.0 1.0))))
  (t-check "collinear/opposite/orthogonal helpers"
    (and (ctr-is-collinear 0 2) (ctr-is-opposite 0 2) (not (ctr-is-opposite 0 0))
         (ctr-is-orthogonal 0 1) (ctr-is-orthogonal 3 0) (not (ctr-is-orthogonal 0 2))))

  (princ "
T16 measured config (D:/BLOCK blocks), WIDTH 300")
  (setq *CTR-FITTING-CONFIG* saved-cfg)
  (t-reset)
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (3000.0 2000.0))))))
  (setq ops (t-ops plan "FITTING"))
  (t-check "elbow scale = 300/39 = 7.6923" (t-near (/ 300.0 39.0) (nth 6 (car ops))))
  (t-check "elbow rot 90 (arms W+N), offset 0" (t-near (/ pi 2.0) (nth 4 (car ops))))
  (setq ops (t-ops plan "STRAIGHT"))
  (t-check "AB trimmed by 62*7.6923 = 476.92 at elbow end"
    (t-pt-near (nth 2 (car ops)) (list (- 3000.0 (* 62.0 (/ 300.0 39.0))) 0.0)))
  (t-check "no NEEDS_USER_CONFIRMATION with measured config" (not (t-log-has "NEEDS_USER_CONFIRMATION")))
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (6000.0 0.0))) (300.0 ((3000.0 2000.0) (3000.0 0.0))))))
  (setq ops (t-ops plan "FITTING"))
  (t-check "tee branch North: block drawn branch-South -> rot 180, scale 300/49"
    (and (t-near pi (nth 4 (car ops))) (t-near (/ 300.0 49.0) (nth 6 (car ops)))))
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (6000.0 0.0))) (300.0 ((3000.0 -2000.0) (3000.0 0.0))))))
  (t-check "tee branch South: rot 360 (block already drawn branch-South)"
    (t-near (* 2.0 pi) (nth 4 (car (t-ops plan "FITTING")))))
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (6000.0 0.0))) (300.0 ((3000.0 2000.0) (3000.0 0.0))))))
  (t-check "tee straights trimmed 67.5*300/49 = 413.27 on main and branch"
    (t-pt-near (nth 2 (car (t-ops plan "STRAIGHT"))) (list (- 3000.0 (* 67.5 (/ 300.0 49.0))) 0.0)))
  (setq plan (t-plan '((300.0 ((0.0 0.0) (3000.0 0.0) (6000.0 0.0))) (300.0 ((3000.0 2000.0) (3000.0 -2000.0))))))
  (setq ops (t-ops plan "FITTING"))
  (t-check "cross scale 300/59, rot 0" (and (= 1 (length ops)) (t-near (/ 300.0 59.0) (nth 6 (car ops))) (t-near 0.0 (nth 4 (car ops)))))

  (princ "
T16b ortho snap of freehand picks")
  (t-check "(0,0)->(3000,7) snaps to (3000,0)" (t-pt-near (ctr-snap-ortho '(0.0 0.0) '(3000.0 7.0)) '(3000.0 0.0)))
  (t-check "(3000,0)->(3009,2000) snaps to (3000,2000)" (t-pt-near (ctr-snap-ortho '(3000.0 0.0) '(3009.0 2000.0)) '(3000.0 2000.0)))
  (t-check "westward and southward picks" (and (t-pt-near (ctr-snap-ortho '(0.0 0.0) '(-500.0 -20.0)) '(-500.0 0.0)) (t-pt-near (ctr-snap-ortho '(0.0 0.0) '(15.0 -900.0)) '(0.0 -900.0))))
  (t-check "snapped point is always orthogonal" (= 0 (ctr-direction '(0.0 0.0) (ctr-snap-ortho '(0.0 0.0) '(3000.0 7.0)))))

  (princ "
T17 per-width entries override proportional scaling")
  (setq *CTR-FITTING-CONFIG*
    (list (list (cons "TYPE" "ELBOW") (cons "BLOCK" "E300") (cons "WIDTH" 300.0) (cons "SCALE" 2.0) (cons "TAKEOFF" 100.0) (cons "ROTATION_OFFSET" 0.0) (cons "BASE_OFFSET" (list 0.0 0.0)))
          (list (cons "TYPE" "ELBOW") (cons "BLOCK" "E450") (cons "WIDTH" 450.0) (cons "SCALE" 3.0) (cons "TAKEOFF" 130.0) (cons "ROTATION_OFFSET" 0.0) (cons "BASE_OFFSET" (list 0.0 0.0)))))
  (t-check "300 -> E300 scale 2, takeoff 200" (and (= "E300" (ctr-cfg-get (ctr-get-fitting-config "ELBOW" 300.0) "BLOCK")) (t-near 2.0 (ctr-get-scale "ELBOW" 300.0)) (t-near 200.0 (ctr-get-takeoff "ELBOW" 300.0 "MAIN"))))
  (t-check "450 -> E450 scale 3, takeoff 390 (not 1.5x of 300)" (and (t-near 3.0 (ctr-get-scale "ELBOW" 450.0)) (t-near 390.0 (ctr-get-takeoff "ELBOW" 450.0 "MAIN"))))
  (t-check "600 with no entry -> no config" (null (ctr-get-fitting-config "ELBOW" 600.0)))

  (princ "
T25 GENERATED_LADDER rung centres (pure geometry, no AutoCAD)")
  (t-check "length 1000: 4 rungs at 125/375/625/875"
    (equal (ctr-ladder-rung-centers 1000.0 125.0 250.0 40.0) '(125.0 375.0 625.0 875.0)))
  (t-check "length 2000: 8 rungs"
    (equal (ctr-ladder-rung-centers 2000.0 125.0 250.0 40.0)
           '(125.0 375.0 625.0 875.0 1125.0 1375.0 1625.0 1875.0)))
  (t-check "length 3000: 12 rungs, none overhang (last centre 2875, +rw/2=2895<=3000)"
    (= 12 (length (ctr-ladder-rung-centers 3000.0 125.0 250.0 40.0))))
  (t-check "no rung overhangs either end for any of the three lengths"
    (and (ctr-none-overhang (ctr-ladder-rung-centers 1000.0 125.0 250.0 40.0) 1000.0 40.0)
         (ctr-none-overhang (ctr-ladder-rung-centers 2000.0 125.0 250.0 40.0) 2000.0 40.0)
         (ctr-none-overhang (ctr-ladder-rung-centers 3000.0 125.0 250.0 40.0) 3000.0 40.0)))
  (t-check "short segment (only 100 long): no rungs fit, still returns cleanly"
    (null (ctr-ladder-rung-centers 100.0 125.0 250.0 40.0)))
  (t-check "CONFIRMED vs real GUI: length 1100 -> still 4 rungs (floor(1100/250)=4)"
    (= 4 (length (ctr-ladder-rung-centers 1100.0 125.0 250.0 40.0))))
  (t-check "CONFIRMED vs real GUI: length 1150 -> still 4 (NOT 5, rules out a fit/overhang-based count)"
    (= 4 (length (ctr-ladder-rung-centers 1150.0 125.0 250.0 40.0))))
  (t-check "length 1250 -> 5th rung appears exactly at the 250 boundary"
    (= 5 (length (ctr-ladder-rung-centers 1250.0 125.0 250.0 40.0))))
  (t-check "count is simply floor(length/spacing), independent of rung width"
    (equal (ctr-ladder-rung-centers 1150.0 125.0 250.0 40.0)
           (ctr-ladder-rung-centers 1150.0 125.0 250.0 10.0)))
  (t-check "oriented rect: horizontal segment, width 750, rail offset -> outer envelope +-375"
    (equal (ctr-oriented-rect '(0.0 0.0) 1.0 0.0 0.0 1.0 500.0 365.0)
           (list '(-500.0 365.0) '(500.0 365.0) '(500.0 -365.0) '(-500.0 -365.0))))

  (princ "
T18 profile isolation (Test A)")
  (setq *CTR-FITTING-CONFIG* saved-cfg)   ; restore DEFAULT's real config (T17 left a test-only table)
  (setq net (ctr-build-network (list (list 300.0 "DEFAULT" (list (list 0.0 0.0) (list 3000.0 0.0)))
                                      (list 300.0 "SCADA_BASIC" (list (list 0.0 5000.0) (list 3000.0 5000.0))))))
  (t-check "path A segment keeps profile DEFAULT" (= "DEFAULT" (ctr-seg-profile (car (cadr net)))))
  (t-check "path B segment keeps profile SCADA_BASIC" (= "SCADA_BASIC" (ctr-seg-profile (cadr (cadr net)))))
  (setq plan (ctr-plan net 't-avail))
  (t-check "2 straights, one per profile, no cross-talk errors" (and (= 2 (t-count (car plan) "STRAIGHT")) (null (cadr plan))))

  (princ "
T19 SCADA_BASIC elbow (Test C)")
  (t-reset)
  (setq net (ctr-build-network (list (list 300.0 "SCADA_BASIC" (list (list 0.0 0.0) (list 3000.0 0.0) (list 3000.0 2000.0))))))
  (setq info (t-node-info net (list 3000.0 0.0)))
  (t-check "classified ELBOW regardless of profile (topology is profile-agnostic)" (= "ELBOW" (cdr (assoc "TYPE" info))))
  (setq plan (ctr-plan net 't-avail))
  (setq ops (t-ops plan "FITTING"))
  (t-check "1 elbow, block = SCADA_BASIC$SCADA_TRAY_ELBOW (aliased, no collision with DEFAULT)"
    (and (= 1 (length ops)) (= "SCADA_BASIC$SCADA_TRAY_ELBOW" (nth 2 (car ops)))))
  (t-check "elbow scale = 300/29, takeoff-derived trim = 300*57/29 at the bend"
    (t-near (/ 300.0 29.0) (nth 6 (car ops))))
  (setq ops (t-ops plan "STRAIGHT"))
  (t-check "straights carry profile SCADA_BASIC" (= "SCADA_BASIC" (nth 5 (car ops))))

  (princ "
T20 SCADA_BASIC tee (Test D)")
  (t-reset)
  (setq net (ctr-build-network (list (list 300.0 "SCADA_BASIC" (list (list 0.0 0.0) (list 3000.0 0.0) (list 6000.0 0.0)))
                                      (list 300.0 "SCADA_BASIC" (list (list 3000.0 2000.0) (list 3000.0 0.0))))))
  (setq plan (ctr-plan net 't-avail))
  (setq ops (t-ops plan "FITTING"))
  (t-check "1 tee, block = SCADA_BASIC$SCADA_TRAY_TEE" (and (= 1 (length ops)) (= "SCADA_BASIC$SCADA_TRAY_TEE" (nth 2 (car ops)))))
  (t-check "CONFIRMED dims: scale = 300/29, rotation 0 (branch already drawn North)"
    (and (not (t-log-has "TEE TAKEOFF not configured"))
         (t-near (/ 300.0 29.0) (nth 6 (car ops))) (t-near 0.0 (nth 4 (car ops)))))
  (setq ops (t-ops plan "STRAIGHT"))
  (t-check "main straights trimmed by 57*300/29=589.66; branch ALSO 57 (corrected from 42, see block_spec_measured.md)"
    (and (t-pt-near (nth 2 (car ops)) (list (- 3000.0 (* 57.0 (/ 300.0 29.0))) 0.0))
         (t-pt-near (nth 2 (caddr ops)) (list 3000.0 (* 57.0 (/ 300.0 29.0))))))

  (princ "
T21 SCADA_BASIC cross NOW SUPPORTED (was Test E: rejected; CROSS config added)")
  (t-reset)
  (setq net (ctr-build-network (list (list 300.0 "SCADA_BASIC" (list (list 0.0 0.0) (list 3000.0 0.0) (list 6000.0 0.0)))
                                      (list 300.0 "SCADA_BASIC" (list (list 3000.0 2000.0) (list 3000.0 0.0) (list 3000.0 -2000.0))))))
  (setq info (t-node-info net (list 3000.0 0.0)))
  (t-check "topology says CROSS" (= "CROSS" (cdr (assoc "TYPE" info))))
  (setq plan (ctr-plan net 't-avail))
  (t-check "1 CROSS fitting inserted, block = SCADA_BASIC$SCADA_TRAY_CROSS, rotation 0"
    (and (= 1 (t-count-fit (car plan) "CROSS"))
         (= "SCADA_BASIC$SCADA_TRAY_CROSS" (nth 2 (car (t-ops plan "FITTING"))))
         (t-near 0.0 (nth 4 (car (t-ops plan "FITTING"))))))
  (t-check "cross scale = 300/29, no NEEDS_USER_CONFIRMATION" (and (t-near (/ 300.0 29.0) (nth 6 (car (t-ops plan "FITTING")))) (not (t-log-has "NEEDS_USER_CONFIRMATION"))))
  (t-check "4 straights, all trimmed by 57*300/29=589.66 at the cross"
    (and (= 4 (t-count (car plan) "STRAIGHT"))
         (t-pt-near (nth 2 (car (t-ops plan "STRAIGHT"))) (list (- 3000.0 (* 57.0 (/ 300.0 29.0))) 0.0))))
  (t-check "no PROFILE errors" (null (cadr plan)))
  (t-check "DEFAULT profile still supports CROSS unaffected"
    (ctr-profile-supports-p "DEFAULT" "CROSS"))
  (t-check "ctr-profile-supports-p directly: SCADA_BASIC/CROSS now T"
    (and (ctr-profile-supports-p "SCADA_BASIC" "CROSS") (ctr-profile-supports-p "SCADA_BASIC" "ELBOW")))

  (princ "
T22 mixed profiles at one node are rejected, not silently merged")
  (t-reset)
  (setq plan (t-plan (list (list 300.0 "DEFAULT" (list (list 0.0 0.0) (list 3000.0 0.0)))
                           (list 300.0 "SCADA_BASIC" (list (list 3000.0 2000.0) (list 3000.0 0.0))))))
  (t-check "PROFILE_MISMATCH at the shared node, nothing generated there"
    (t-log-has-err (cadr plan) "PROFILE_MISMATCH"))

  (princ "
T23 CTRAYUPDATE re-render is per-path profile-aware (Test F)")
  (t-reset)
  (setq net (ctr-build-network (list (list 300.0 "SCADA_BASIC" (list (list 0.0 0.0) (list 3000.0 0.0) (list 3000.0 2000.0))))))
  (setq *CTR-CURRENT-PROFILE* "DEFAULT")   ; simulate: session's current profile changed, stored path is untouched
  (setq plan (ctr-plan net 't-avail))
  (t-check "existing SCADA_BASIC path still renders with its OWN stored profile, not the new session default"
    (= "SCADA_BASIC$SCADA_TRAY_ELBOW" (nth 2 (car (t-ops plan "FITTING")))))
  (setq *CTR-CURRENT-PROFILE* "DEFAULT")

  (princ "
T24 legacy 2-tuple path (width pts) still defaults to profile DEFAULT")
  (t-reset)
  (setq net (ctr-build-network (list (list 300.0 (list (list 0.0 0.0) (list 3000.0 0.0) (list 3000.0 2000.0))))))
  (t-check "old-format path (no profile) -> segments default DEFAULT" (= "DEFAULT" (ctr-seg-profile (car (cadr net)))))
  (setq plan (ctr-plan net 't-avail))
  (t-check "renders exactly like before profiles existed (bare block name, no $ prefix)"
    (= "SCADA_TRAY_ELBOW" (nth 2 (car (t-ops plan "FITTING")))))

  (princ "
T26 SCADA_V2 ELBOW_V2 corrected tangent-geometry model (real-engine CONFIRMED,
    all 4 rail joints 0.0000mm on this exact scenario -- see
    block_spec_measured.md). Earlier per-rail-longitudinal-termination
    belief was a coordinate mix-up (radii from the arc's own pivot mistaken
    for per-rail longitudinal takeoffs); the corrected model is an ordinary
    flat-cut: BASE_OFFSET=(-576,576) moves the router's fitting-centre
    reference from the arc pivot to the true sharp mitre corner, after which
    BOTH rails share one TAKEOFF=576 and differ only in the transverse
    (+-BLOCK_WIDTH/2) direction, same as any other GENERATED_LADDER elbow.")
  (setq *CTR-FITTING-CONFIG* (ctr-profile-fittings "SCADA_V2"))
  (setq cfg (ctr-get-fitting-config "ELBOW" nil))
  (setq *CTR-FITTING-CONFIG* saved-cfg)
  (t-check "SCADA_V2 ELBOW BLOCK_WIDTH=622.9333" (t-near 622.9333 (ctr-cfg-get cfg "BLOCK_WIDTH")))
  (t-check "SCADA_V2 ELBOW TAKEOFF=576.0" (t-near 576.0 (ctr-cfg-get cfg "TAKEOFF")))
  (t-check "SCADA_V2 ELBOW BASE_OFFSET=(-576,576)"
    (t-pt-near (ctr-cfg-get cfg "BASE_OFFSET") '(-576.0 576.0)))
  (t-check "SCADA_V2 ELBOW ROTATION_OFFSET=270" (t-near 270.0 (ctr-cfg-get cfg "ROTATION_OFFSET")))
  (t-check "no leftover RAIL_TERMINATION/RAIL_TAKEOFF_* keys (retracted architecture fully removed)"
    (and (null (assoc "RAIL_TERMINATION" cfg)) (null (assoc "RAIL_TAKEOFF_NEAR" cfg))
         (null (assoc "RAIL_TAKEOFF_FAR" cfg))))

  (t-reset)
  (setq plan (t-plan (list (list 622.9333 "SCADA_V2"
                                 (list (list 0.0 0.0) (list 3000.0 0.0) (list 3000.0 2000.0))))))
  (t-check "no planner errors" (null (cadr plan)))
  (t-check "2 straights + 1 elbow" (and (= 2 (t-count (car plan) "STRAIGHT"))
                                        (= 1 (t-count-fit (car plan) "ELBOW"))))
  (t-check "West+North native block needs ZERO net rotation (90 base + 270 offset = 360 = 0), real-engine confirmed"
    (t-near 0.0 (rem (nth 4 (car (t-ops plan "FITTING"))) (* 2.0 pi))))
  (t-check "insert_pt = node + BASE_OFFSET = (3000,0)+(-576,576) = (2424,576), real-engine confirmed"
    (t-pt-near (nth 3 (car (t-ops plan "FITTING"))) '(2424.0 576.0)))
  (setq ops (t-ops plan "STRAIGHT"))
  (setq in-op nil out-op nil)
  (foreach o ops
    (if (t-pt-near (nth 1 o) '(0.0 0.0)) (setq in-op o))
    (if (t-pt-near (nth 2 o) '(3000.0 2000.0)) (setq out-op o)))
  (t-check "found both straights" (and in-op out-op))
  (t-check "incoming: single flat TAKEOFF=576, trimmed to (2424,0) -- NOT per-rail"
    (t-pt-near (nth 2 in-op) '(2424.0 0.0)))
  (t-check "outgoing: single flat TAKEOFF=576, starts at (3000,576) -- NOT per-rail"
    (t-pt-near (nth 1 out-op) '(3000.0 576.0)))
  (t-check "STRAIGHT op is the plain 6-field tuple again (no rail-override fields)"
    (and (= 6 (length in-op)) (= 6 (length out-op))))

  (setq *CTR-FITTING-CONFIG* saved-cfg *CTR-QUIET* nil)
  (princ (strcat "\n\nRESULT: " (itoa *T-PASS*) " passed, " (itoa *T-FAIL*) " failed."))
  (princ)
  *T-FAIL*)

(defun ctr-none-overhang (centers length rw / c ok)
  (setq ok T)
  (foreach c centers
    (if (or (< (- c (/ rw 2.0)) -0.0001) (> (+ c (/ rw 2.0)) (+ length 0.0001))) (setq ok nil)))
  ok)

(defun t-log-has-err (errs code / hit e)
  (foreach e errs (if (= (car e) code) (setq hit T))
    (if (wcmatch-lite (caddr e) code) (setq hit T)))
  hit)

(defun t-count-log (text / n l)
  (setq n 0)
  (foreach l *CTR-LOG* (if (wcmatch-lite l text) (setq n (1+ n))))
  n)

(princ "\nctr tests loaded: run (ctr-run-tests)")
(princ)
