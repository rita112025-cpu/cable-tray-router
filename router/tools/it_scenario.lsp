;;; Integration scenario, run inside accoreconsole by tools/acc_integration.py
;;; (works on a scratch copy of a drawing; never on D:\BLOCK originals)
(load "D:/BLOCK/router/cable_tray_router.lsp")

(defun it-count (/ ss)
  (setq ss (ssget "_X" (list (cons 8 "SCADA-TRAY"))))
  (if ss (sslength ss) 0))
(defun it-mark (tag) (princ (strcat "\nIT_COUNT " tag " = " (itoa (it-count)))) (princ))
(defun it-mkpath (pts w) (ctr-ensure-layers) (ctr-make-path pts w "DEFAULT"))
(defun it-mkpath-p (pts w profile) (ctr-ensure-layers) (ctr-make-path pts w profile))

(defun it-stage1 ()
  (ctr-ensure-layers)
  ;; Phase 1: Straight Elbow Straight Elbow Straight
  (it-mkpath '((0.0 0.0) (3000.0 0.0) (3000.0 2000.0) (5000.0 2000.0)) 300.0)
  ;; Phase 2: Tee
  (it-mkpath '((0.0 10000.0) (3000.0 10000.0) (6000.0 10000.0)) 300.0)
  (it-mkpath '((3000.0 12000.0) (3000.0 10000.0)) 300.0)
  ;; Phase 3: Cross
  (it-mkpath '((0.0 20000.0) (3000.0 20000.0) (6000.0 20000.0)) 300.0)
  (it-mkpath '((3000.0 22000.0) (3000.0 20000.0) (3000.0 18000.0)) 300.0)
  ;; unsupported (45 deg)
  (it-mkpath '((0.0 30000.0) (1000.0 31000.0)) 300.0)
  (c:CTRAYUPDATE)
  (it-mark "stage1"))

;; Phase 4: edit PATH, update; then UNDO must restore the previous result
(defun it-stage2-undo ()
  (it-mark "before-edit")
  (it-mkpath '((3000.0 0.0) (3000.0 -2000.0)) 300.0)
  (c:CTRAYUPDATE)
  (it-mark "after-edit-update")
  (command "_.UNDO" "1")
  (it-mark "after-undo"))
(defun it-stage2 ()
  (c:CTRAYUPDATE)
  (it-mark "stage2-final"))
(princ)
