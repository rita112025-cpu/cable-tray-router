;;; Straight/Elbow/Tee connection-plane delta measurement.
;;; Builds Test A (4 elbow orientations) and Test B (tee) with the REAL
;;; router, dumps every LWPOLYLINE/LINE vertex BEFORE exploding fittings
;;; (captures the GENERATED_LADDER straight rails), explodes every fitting
;;; INSERT in place, then dumps again (captures the fitting's own rail
;;; geometry as raw entities). Python does all the joint-matching + delta math.
(load "D:/BLOCK/router/tools/it_scenario.lsp")

(defun it-dump-all (label / ss i n en ed pts p lay)
  (setq ss (ssget "_X" (list '(-4 . "<OR")
                             (cons 0 "LWPOLYLINE") (cons 0 "LINE") '(-4 . "OR>"))))
  (setq n (if ss (sslength ss) 0) i 0)
  (while (< i n)
    (setq en (ssname ss i) ed (entget en) pts nil lay (cdr (assoc 8 ed)))
    (foreach p ed (if (member (car p) (list 10 11)) (setq pts (cons (cdr p) pts))))
    (princ (strcat "\nV " label " " lay " " (cdr (assoc 5 ed)) " "))
    (foreach p pts (princ (strcat "(" (rtos (car p) 2 4) " " (rtos (cadr p) 2 4) ")")))
    (setq i (1+ i)))
  (princ))

(defun it-delta-scenario (/ ss i n)
  (ctr-ensure-layers)
  ;; Test A: elbow, all 4 direction-pairs, width 300
  (it-mkpath-p (list (list 0.0 0.0) (list 3000.0 0.0) (list 3000.0 2000.0)) 300.0 "SCADA_BASIC")      ; dirs W+N at (3000,0)
  (it-mkpath-p (list (list 0.0 10000.0) (list 3000.0 10000.0) (list 3000.0 8000.0)) 300.0 "SCADA_BASIC") ; dirs W+S at (3000,10000)
  (it-mkpath-p (list (list 10000.0 0.0) (list 7000.0 0.0) (list 7000.0 2000.0)) 300.0 "SCADA_BASIC")     ; dirs E+N at (7000,0)
  (it-mkpath-p (list (list 10000.0 10000.0) (list 7000.0 10000.0) (list 7000.0 8000.0)) 300.0 "SCADA_BASIC") ; dirs E+S at (7000,10000)
  ;; Test B: tee, main run + branch, width 300
  (it-mkpath-p (list (list 0.0 20000.0) (list 3000.0 20000.0) (list 6000.0 20000.0)) 300.0 "SCADA_BASIC")
  (it-mkpath-p (list (list 3000.0 22000.0) (list 3000.0 20000.0)) 300.0 "SCADA_BASIC")
  (c:CTRAYUPDATE)
  (princ (strcat "\nOBJCOUNT-BEFORE=" (itoa (it-count))))
  (it-dump-all "BEFORE")
  (setq ss (ssget "_X" (list (cons 8 "SCADA-TRAY") (cons 0 "INSERT"))))
  (setq n (if ss (sslength ss) 0) i 0)
  (princ (strcat "\nFITTING-INSERT-COUNT=" (itoa n)))
  (while (< i n)
    (setq en (ssname ss i))
    (setq ed (entget en))
    (princ (strcat "\nINS " (cdr (assoc 2 ed)) " ip=(" (rtos (cadr (assoc 10 ed)) 2 4) " "
                   (rtos (caddr (assoc 10 ed)) 2 4) ") rot=" (rtos (cdr (assoc 50 ed)) 2 6)
                   " scale=" (rtos (cdr (assoc 41 ed)) 2 6)))
    (command "_.EXPLODE" (ssadd en (ssadd)))
    (setq i (1+ i)))
  (princ "\nEXPLODE-ALL-DONE")
  (setq ss (ssget "_X" (list (cons 8 "SCADA-TRAY") (cons 0 "INSERT"))))
  (princ (strcat "\nINSERTS-REMAINING=" (itoa (if ss (sslength ss) 0))))
  (princ (strcat "\nGLOBAL-ALL-ENTITIES=" (itoa (ctr-count-all))))
  (it-dump-all "AFTER")
  (princ))
(princ)
