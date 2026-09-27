;;; Straight/Elbow/Tee joint check for SCADA_BASIC, run via acc_joint.py
(load "D:/BLOCK/router/tools/it_scenario.lsp")

(defun it-explode-all-inserts (layer / ss i n en ss1)
  (setq ss (ssget "_X" (list (cons 8 layer) (cons 0 "INSERT"))))
  (setq n (if ss (sslength ss) 0) i 0)
  (while (< i n)
    (setq en (ssname ss i))
    (setq ss1 (ssadd en (ssadd)))
    (command "_.EXPLODE" ss1 "")
    (setq i (1+ i)))
  (princ (strcat "\nEXPLODED " (itoa n) " insert(s) on " layer)))

(defun it-dump-all-lwpl (layer / ss i n en ed pts p mnx mny mxx mxy)
  (setq ss (ssget "_X" (list (cons 8 layer) (cons 0 "LWPOLYLINE"))))
  (setq n (if ss (sslength ss) 0) i 0)
  (while (< i n)
    (setq en (ssname ss i) ed (entget en) pts nil)
    (foreach p ed (if (= (car p) 10) (setq pts (cons (cdr p) pts))))
    (setq mnx (car (car pts)) mxx mnx mny (cadr (car pts)) mxy mny)
    (foreach p pts
      (setq mnx (min mnx (car p)) mxx (max mxx (car p))
            mny (min mny (cadr p)) mxy (max mxy (cadr p))))
    (princ (strcat "\nJPOLY " (rtos mnx 2 3) "," (rtos mny 2 3) ","
                   (rtos mxx 2 3) "," (rtos mxy 2 3)))
    (setq i (1+ i)))
  (princ))

(defun it-joint-scenario ()
  (ctr-ensure-layers)
  ;; Elbow: A(0,0)-B(3000,0)-C(3000,2000), width 300
  (it-mkpath-p (list (list 0.0 0.0) (list 3000.0 0.0) (list 3000.0 2000.0)) 300.0 "SCADA_BASIC")
  ;; Tee: A(0,10000)-B(3000,10000)-C(6000,10000) + branch D(3000,12000)-B, width 300
  (it-mkpath-p (list (list 0.0 10000.0) (list 3000.0 10000.0) (list 6000.0 10000.0)) 300.0 "SCADA_BASIC")
  (it-mkpath-p (list (list 3000.0 12000.0) (list 3000.0 10000.0)) 300.0 "SCADA_BASIC")
  (c:CTRAYUPDATE)
  (princ (strcat "\nJOINT_CHECK tray-total=" (itoa (it-count))))
  (it-dump-all-lwpl "SCADA-TRAY")
  (princ "\n--- exploding fittings to inspect real rail geometry ---")
  (it-explode-all-inserts "SCADA-TRAY")
  (it-dump-all-lwpl "SCADA-TRAY")
  (princ))
(princ)
