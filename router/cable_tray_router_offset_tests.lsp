;;; ====================================================================
;;; cable_tray_router_offset_tests.lsp -- tests for section 10 (CTOFFSET).
;;; Pure functions only; no AutoCAD objects.  Needs cable_tray_router.lsp and
;;; cable_tray_router_tests.lsp (t-check / t-near / *T-PASS*) loaded first.
;;; Headless: python tools/run_tests.py
;;; ====================================================================
(defun t-off-near (res key expected tol)
  (< (abs (- (cdr (assoc key res)) expected)) tol))
(defun t-off-has-line (lines text / hit l)
  (foreach l lines (if (= l text) (setq hit T)))
  hit)

(defun ctr-run-offset-tests (/ r f fa lines)
  (princ "\n-- CTOFFSET (vertical offset engine) --")

  ;; Case 1: DOWN, angle 30
  (setq r (ctr-offset-from-angle 3300.0 2700.0 30.0))
  (t-check "C1 delta_z = -600" (t-off-near r "DELTA_Z" -600.0 1e-9))
  (t-check "C1 abs delta 600" (t-off-near r "ABSOLUTE_DELTA_Z" 600.0 1e-9))
  (t-check "C1 direction DOWN" (= "DOWN" (cdr (assoc "DIRECTION" r))))
  (t-check "C1 horizontal_run 1039.2305" (t-off-near r "HORIZONTAL_RUN" 1039.2305 0.0001))
  (t-check "C1 slope_length 1200" (t-off-near r "SLOPE_LENGTH" 1200.0 1e-6))
  (t-check "C1 slope_percent 57.735" (t-off-near r "SLOPE_PERCENT" 57.735 0.001))
  (t-check "C1 angle 30" (t-off-near r "ANGLE_DEG" 30.0 1e-9))
  (t-check "C1 offset_mode GEOMETRIC" (= "GEOMETRIC" (cdr (assoc "OFFSET_MODE" r))))
  (setq lines (ctr-offset-format r))
  (t-check "C1 format Delta Z -600.00 mm" (t-off-has-line lines "Delta Z         : -600.00 mm"))
  (t-check "C1 format Horizontal Run 1039.23 mm" (t-off-has-line lines "Horizontal Run  : 1039.23 mm"))
  (t-check "C1 format Slope Length 1200.00 mm" (t-off-has-line lines "Slope Length    : 1200.00 mm"))
  (t-check "C1 format Slope 57.74 %" (t-off-has-line lines "Slope           : 57.74 %"))
  (t-check "C1 format Angle 30.00 deg" (t-off-has-line lines "Angle           : 30.00 deg"))
  (t-check "C1 format Direction DOWN" (t-off-has-line lines "Direction       : DOWN"))

  ;; Case 2: UP, angle 30
  (setq r (ctr-offset-from-angle 2700.0 3300.0 30.0))
  (t-check "C2 delta_z = +600" (t-off-near r "DELTA_Z" 600.0 1e-9))
  (t-check "C2 direction UP" (= "UP" (cdr (assoc "DIRECTION" r))))
  (t-check "C2 horizontal_run 1039.2305" (t-off-near r "HORIZONTAL_RUN" 1039.2305 0.0001))
  (t-check "C2 slope_length 1200" (t-off-near r "SLOPE_LENGTH" 1200.0 1e-6))

  ;; Case 3: RUN mode
  (setq r (ctr-offset-from-run 3300.0 2700.0 3000.0))
  (t-check "C3 delta_z = -600" (t-off-near r "DELTA_Z" -600.0 1e-9))
  (t-check "C3 direction DOWN" (= "DOWN" (cdr (assoc "DIRECTION" r))))
  (t-check "C3 angle 11.3099" (t-off-near r "ANGLE_DEG" 11.3099 0.0001))
  (t-check "C3 slope_percent 20" (t-off-near r "SLOPE_PERCENT" 20.0 1e-9))
  (t-check "C3 slope_ratio 0.2" (t-off-near r "SLOPE_RATIO" 0.2 1e-12))
  (t-check "C3 slope_length 3059.4117" (t-off-near r "SLOPE_LENGTH" 3059.4117 0.0001))
  (setq lines (ctr-offset-format r))
  (t-check "C3 format Angle 11.31 deg" (t-off-has-line lines "Angle           : 11.31 deg"))
  (t-check "C3 format Slope Length 3059.41 mm" (t-off-has-line lines "Slope Length    : 3059.41 mm"))
  (t-check "C3 format Slope 20.00 %" (t-off-has-line lines "Slope           : 20.00 %"))

  ;; Case 4: space check, dz 600, available 800
  (setq f (ctr-offset-feasibility 600.0 800.0))
  (t-check "C4 minimum required angle 36.8699" (t-off-near f "MIN_ANGLE_DEG" 36.8699 0.0001))
  (setq fa (cdr (assoc "ANGLES" f)))
  (t-check "C4 four standard angles" (= 4 (length fa)))
  (t-check "C4 15 NG"   (not (caddr (nth 0 fa))))
  (t-check "C4 22.5 NG" (not (caddr (nth 1 fa))))
  (t-check "C4 30 NG"   (not (caddr (nth 2 fa))))
  (t-check "C4 45 OK"   (caddr (nth 3 fa)))
  (t-check "C4 45 required run = 600" (t-near 600.0 (cadr (nth 3 fa)) ))
  (setq r (ctr-offset-from-angle 3300.0 2700.0 30.0))
  (setq lines (ctr-offset-format-space f (cdr (assoc "HORIZONTAL_RUN" r))))
  (t-check "C4 SPACE CHECK : NG" (t-off-has-line lines "SPACE CHECK : NG"))
  (t-check "C4 Required 1039.23" (t-off-has-line lines "Required    : 1039.23 mm"))
  (t-check "C4 Available 800.00" (t-off-has-line lines "Available   : 800.00 mm"))
  (t-check "C4 Shortage 239.23" (t-off-has-line lines "Shortage    : 239.23 mm"))
  (t-check "C4 Minimum angle 36.87" (t-off-has-line lines "Minimum required angle : 36.87 deg"))
  (t-check "C4 15.0 NG / 45.0 OK lines" (and (t-off-has-line lines "15.0 deg   NG") (t-off-has-line lines "45.0 deg   OK")))
  (t-check "C4 22.5 NG / 30.0 NG lines" (and (t-off-has-line lines "22.5 deg   NG") (t-off-has-line lines "30.0 deg   NG")))
  ;; exact boundary: available == required is OK (no safety factor, no float-noise NG)
  (t-check "C4b avail 600 -> 45 OK" (caddr (nth 3 (cdr (assoc "ANGLES" (ctr-offset-feasibility 600.0 600.0))))))
  (t-check "C4b avail 599.99 -> 45 NG" (not (caddr (nth 3 (cdr (assoc "ANGLES" (ctr-offset-feasibility 600.0 599.99)))))))
  (t-check "C4c space OK block when enough" (t-off-has-line (ctr-offset-format-space (ctr-offset-feasibility 600.0 2000.0) 1039.2305) "SPACE CHECK : OK"))

  ;; Case 5: LEVEL
  (setq r (ctr-offset-from-angle 3000.0 3000.0 30.0))
  (t-check "C5 level delta 0" (t-off-near r "DELTA_Z" 0.0 1e-12))
  (t-check "C5 level direction" (= "LEVEL" (cdr (assoc "DIRECTION" r))))
  (t-check "C5 level angle 0 / slope 0" (and (t-off-near r "ANGLE_DEG" 0.0 1e-12) (t-off-near r "SLOPE_PERCENT" 0.0 1e-12)))
  (t-check "C5 level ANGLE mode needs no valid angle" (ctr-offset-from-angle 3000.0 3000.0 0.0))
  (t-check "C5 format says No vertical offset required." (t-off-has-line (ctr-offset-format r) "No vertical offset required."))
  (setq r (ctr-offset-from-run 3000.0 3000.0 2500.0))
  (t-check "C5 level RUN: direction LEVEL, slope_length = run" (and (= "LEVEL" (cdr (assoc "DIRECTION" r))) (t-off-near r "SLOPE_LENGTH" 2500.0 1e-9)))
  (t-check "C5 level RUN: angle 0, percent 0" (and (t-off-near r "ANGLE_DEG" 0.0 1e-12) (t-off-near r "SLOPE_PERCENT" 0.0 1e-12)))

  ;; Case 6: illegal input rejected (nil, no error)
  (t-check "C6 run = 0 rejected"    (null (ctr-offset-from-run 3300.0 2700.0 0.0)))
  (t-check "C6 run = -100 rejected" (null (ctr-offset-from-run 3300.0 2700.0 -100.0)))
  (t-check "C6 run non-number rejected" (null (ctr-offset-from-run 3300.0 2700.0 nil)))
  (t-check "C6 angle = 0 rejected"   (null (ctr-offset-from-angle 3300.0 2700.0 0.0)))
  (t-check "C6 angle = 90 rejected"  (null (ctr-offset-from-angle 3300.0 2700.0 90.0)))
  (t-check "C6 angle = -30 rejected" (null (ctr-offset-from-angle 3300.0 2700.0 -30.0)))
  (t-check "C6 angle = 120 rejected" (null (ctr-offset-from-angle 3300.0 2700.0 120.0)))
  (t-check "C6 angle nil rejected"   (null (ctr-offset-from-angle 3300.0 2700.0 nil)))
  (t-check "C6 avail = 0 rejected"   (null (ctr-offset-feasibility 600.0 0.0)))
  (t-check "C6 avail = -5 rejected"  (null (ctr-offset-feasibility 600.0 -5.0)))
  (t-check "C6 required-run invalid angle -> nil" (null (ctr-offset-required-run 600.0 90.0)))

  ;; Extra: integer inputs, formatting, annotation, mode reservation
  (setq r (ctr-offset-from-angle 3300 2700 30))
  (t-check "X1 integer inputs accepted" (t-off-near r "HORIZONTAL_RUN" 1039.2305 0.0001))
  (t-check "X2 fmt rounds only at output" (and (= "1039.23" (ctr-offset-fmt 1039.2304845)) (= "0.00" (ctr-offset-fmt -0.0000001))
                                              (= "-600.00" (ctr-offset-fmt -600.0)) (= "0.05" (ctr-offset-fmt 0.05))))
  (t-check "X3 raw value not rounded" (> (abs (- (cdr (assoc "HORIZONTAL_RUN" r)) 1039.23)) 0.0004))
  (setq lines (ctr-offset-annotation r "SCADA TRAY 300W"))
  (t-check "X4 annotation text"
    (and (= (nth 0 lines) "SCADA TRAY 300W") (= (nth 1 lines) "EL.+3300 -> EL.+2700")
         (= (nth 2 lines) "DOWN 600 / 30 deg") (= (nth 3 lines) "RUN=1039 / SLOPE=1200")))
  (t-check "X5 FITTING reserved but not the active mode"
    (and (member "FITTING" *CTR-OFFSET-MODES*) (= "GEOMETRIC" *CTR-OFFSET-MODE*)))
  (t-check "X6 steep 89.9 deg stays finite" (< (cdr (assoc "HORIZONTAL_RUN" (ctr-offset-from-angle 0.0 600.0 89.9))) 2.0))
  (princ)
  *T-FAIL*)

(princ "\nctr offset tests loaded: run (ctr-run-offset-tests)")
(princ)
