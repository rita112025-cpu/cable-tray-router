;;; gui_selftest.lsp -- run inside a NEW BLANK drawing in the AutoCAD GUI.
;;;   (load "D:/BLOCK/router/tools/gui_selftest.lsp")
;;;   (ctr-gui-selftest)
;;; Writes D:/BLOCK/router/gui_selftest_report.txt and prints the same lines.
;;; It creates test objects at far coordinates; close the drawing WITHOUT saving.
(load "D:/BLOCK/router/cable_tray_router.lsp")

(setq *GT-PASS* 0 *GT-FAIL* 0 *GT-FILE* nil)

(defun gt-say (s)
  (princ (strcat "\n" s))
  (if *GT-FILE* (write-line s *GT-FILE*))
  (princ))
(defun gt-check (name ok)
  (if ok (setq *GT-PASS* (1+ *GT-PASS*)) (setq *GT-FAIL* (1+ *GT-FAIL*)))
  (gt-say (strcat (if ok "PASS  " "FAIL  ") name)))
(defun gt-n (layer / ss) (setq ss (ssget "_X" (list (cons 8 layer)))) (if ss (sslength ss) 0))
;; objects on layer inside a window
(defun gt-nw (layer p1 p2 / ss)
  (setq ss (ssget "_C" p1 p2 (list (cons 8 layer)))) (if ss (sslength ss) 0))
(defun gt-mkpath (pts) (ctr-make-path pts 300.0 "DEFAULT"))
(defun gt-mkpath-p (pts w profile) (ctr-make-path pts w profile))

(defun ctr-gui-selftest (/ n1 n2 n3 npath a b)
  (setq *GT-PASS* 0 *GT-FAIL* 0)
  (setq *GT-FILE* (open "D:/BLOCK/router/gui_selftest_report.txt" "w"))
  (gt-say (strcat "ctr GUI selftest  router " *CTR-VERSION* "  ACADVER=" (getvar "ACADVER")))
  (setvar "CMDECHO" 0)
  (ctr-ensure-layers)

  (gt-say "-- A: CTRAYUPDATE from existing paths (Phase 1-3 layout)")
  (gt-mkpath '((0.0 0.0) (3000.0 0.0) (3000.0 2000.0) (5000.0 2000.0)))
  (gt-mkpath '((0.0 10000.0) (3000.0 10000.0) (6000.0 10000.0)))
  (gt-mkpath '((3000.0 12000.0) (3000.0 10000.0)))
  (gt-mkpath '((0.0 20000.0) (3000.0 20000.0) (6000.0 20000.0)))
  (gt-mkpath '((3000.0 22000.0) (3000.0 20000.0) (3000.0 18000.0)))
  (command "CTRAYUPDATE")
  (setq n1 (gt-n "SCADA-TRAY"))
  (gt-check (strcat "CTRAYUPDATE generated 14 objects (got " (itoa n1) ")") (= n1 14))

  (gt-say "-- B: edit PATH, CTRAYUPDATE, then ONE Undo")
  (gt-mkpath '((3000.0 0.0) (3000.0 -2000.0)))
  (setq npath (gt-n "SCADA-TRAY-PATH"))
  (command "CTRAYUPDATE")
  (setq n2 (gt-n "SCADA-TRAY"))
  (gt-check (strcat "after edit: 15 objects (got " (itoa n2) ")") (= n2 15))
  (command "_.U")
  (setq n3 (gt-n "SCADA-TRAY"))
  (gt-check (strcat "ONE undo restores previous result: 14 objects (got " (itoa n3) ")") (= n3 14))
  (gt-check "undo did not delete user centre lines" (= npath (gt-n "SCADA-TRAY-PATH")))

  (gt-say "-- C: interactive CTRAY  (width 300, 3 points, Enter)")
  (setq a (gt-n "SCADA-TRAY-PATH"))
  (command "CTRAY" "300" "0,40000" "3000,40000" "3000,42000" "")
  (gt-check (strcat "CTRAY created 1 path (got " (itoa (- (gt-n "SCADA-TRAY-PATH") a)) ")")
            (= 1 (- (gt-n "SCADA-TRAY-PATH") a)))
  (gt-check (strcat "CTRAY generated 2 straights + 1 elbow near y=40000 (got "
                    (itoa (gt-nw "SCADA-TRAY" '(-500.0 39000.0) '(4000.0 43000.0))) ")")
            (= 3 (gt-nw "SCADA-TRAY" '(-500.0 39000.0) '(4000.0 43000.0))))
  (command "_.U")
  (gt-check "one Undo removes the whole CTRAY result (path + tray in that area)"
            (= 0 (+ (gt-nw "SCADA-TRAY" '(-500.0 39000.0) '(4000.0 43000.0))
                    (gt-nw "SCADA-TRAY-PATH" '(-500.0 39000.0) '(4000.0 43000.0)))))
  (gt-check "earlier results untouched by that undo (14 objects)" (= 14 (gt-n "SCADA-TRAY")))

  (gt-say "-- D: non-orthogonal point is rejected")
  (command "CTRAY" "300" "0,50000" "1000,51000" "")
  (gt-check "45-degree input creates nothing"
            (= 0 (+ (gt-nw "SCADA-TRAY" '(-500.0 49000.0) '(3000.0 52000.0))
                    (gt-nw "SCADA-TRAY-PATH" '(-500.0 49000.0) '(3000.0 52000.0)))))

  (gt-say "-- E: single point / ESC-like empty input")
  (command "CTRAY" "300" "0,60000" "")
  (gt-check "single point creates nothing"
            (= 0 (gt-nw "SCADA-TRAY-PATH" '(-500.0 59000.0) '(3000.0 61000.0))))

  (gt-say (strcat "RESULT: " (itoa *GT-PASS*) " passed, " (itoa *GT-FAIL*) " failed."))
  (close *GT-FILE*) (setq *GT-FILE* nil)
  (princ "\nReport: D:/BLOCK/router/gui_selftest_report.txt  (close this drawing WITHOUT saving)")
  (princ))
(princ "\nRun: (ctr-gui-selftest)")
(princ)
