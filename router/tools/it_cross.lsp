;;; CROSS connection-plane delta measurement, run via acc_cross.py.
;;; Builds the user's exact Test 8 scenario (two crossing paths, WIDTH=300,
;;; SCADA_BASIC) via ctr-make-path + CTU (not a simplified test geometry),
;;; dumps every LWPOLYLINE/LINE vertex before exploding (captures the
;;; GENERATED_LADDER straight rails), explodes the Cross INSERT, dumps again.
(load "D:/BLOCK/router/tools/it_scenario.lsp")

(defun it-dump-all2 (label / ss i n en ed pts p lay)
  (setq ss (ssget "_X" (list '(-4 . "<OR") (cons 0 "LWPOLYLINE") (cons 0 "LINE") '(-4 . "OR>"))))
  (setq n (if ss (sslength ss) 0) i 0)
  (while (< i n)
    (setq en (ssname ss i) ed (entget en) pts nil lay (cdr (assoc 8 ed)))
    (foreach p ed (if (member (car p) (list 10 11)) (setq pts (cons (cdr p) pts))))
    (princ (strcat "\nV " label " " lay " " (cdr (assoc 5 ed)) " "))
    (foreach p pts (princ (strcat "(" (rtos (car p) 2 4) " " (rtos (cadr p) 2 4) ")")))
    (setq i (1+ i)))
  (princ))

(defun it-cross-scenario (/ ss i n en ed)
  (ctr-ensure-layers)
  ;; item 8 exactly: horizontal (0,3000)->(6000,3000), vertical (3000,0)->(3000,6000)
  (it-mkpath-p (list (list 0.0 3000.0) (list 6000.0 3000.0)) 300.0 "SCADA_BASIC")
  (it-mkpath-p (list (list 3000.0 0.0) (list 3000.0 6000.0)) 300.0 "SCADA_BASIC")
  (c:CTU)
  (princ (strcat "\nOBJCOUNT-BEFORE=" (itoa (it-count))))
  (it-dump-all2 "BEFORE")
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
  (it-dump-all2 "AFTER")
  (princ))
(princ)
