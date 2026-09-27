;;; GENERATED_LADDER integration scenario, run via acc_ladder.py
(load "D:/BLOCK/router/tools/it_scenario.lsp")

(defun it-count-poly (/ ss) (setq ss (ssget "_X" (list (cons 8 "SCADA-TRAY") (cons 0 "LWPOLYLINE")))) (if ss (sslength ss) 0))

;; horizontal straights at three lengths (width 750, the confirmed authoring width)
(defun it-ladder-h ()
  (ctr-ensure-layers)
  (it-mkpath-p (list (list 0.0 0.0) (list 1000.0 0.0)) 750.0 "SCADA_BASIC")
  (it-mkpath-p (list (list 0.0 5000.0) (list 2000.0 5000.0)) 750.0 "SCADA_BASIC")
  (it-mkpath-p (list (list 0.0 10000.0) (list 3000.0 10000.0)) 750.0 "SCADA_BASIC")
  ;; vertical straight, width 300
  (it-mkpath-p (list (list 20000.0 0.0) (list 20000.0 1000.0)) 300.0 "SCADA_BASIC")
  (it-mkpath-p (list (list 0.0 20000.0) (list 1100.0 20000.0)) 750.0 "SCADA_BASIC")
  (it-mkpath-p (list (list 0.0 25000.0) (list 1150.0 25000.0)) 750.0 "SCADA_BASIC")
  (it-mkpath-p (list (list 0.0 30000.0) (list 1250.0 30000.0)) 750.0 "SCADA_BASIC")
  (c:CTRAYUPDATE)
  (princ (strcat "\nLADDER_CHECK total-tray=" (itoa (it-count))
                 " polylines=" (itoa (it-count-poly))))
  (princ))

;; dump every LWPOLYLINE's bbox on layer SCADA-TRAY so Python can classify
;; rails vs rungs and measure rung-centre spacing/positions.
(defun it-dump-polys (/ ss i n en ed pts p mnx mny mxx mxy)
  (setq ss (ssget "_X" (list (cons 8 "SCADA-TRAY") (cons 0 "LWPOLYLINE"))))
  (setq n (if ss (sslength ss) 0) i 0)
  (while (< i n)
    (setq en (ssname ss i) ed (entget en) pts nil)
    (foreach p ed (if (= (car p) 10) (setq pts (cons (cdr p) pts))))
    (setq mnx (car (car pts)) mxx mnx mny (cadr (car pts)) mxy mny)
    (foreach p pts
      (setq mnx (min mnx (car p)) mxx (max mxx (car p))
            mny (min mny (cadr p)) mxy (max mxy (cadr p))))
    (princ (strcat "\nPOLY " (rtos mnx 2 2) "," (rtos mny 2 2) ","
                   (rtos mxx 2 2) "," (rtos mxy 2 2)))
    (setq i (1+ i)))
  (princ))
(princ)
