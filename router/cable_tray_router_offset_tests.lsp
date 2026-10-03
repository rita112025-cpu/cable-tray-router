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

(defun t-off-has-sub (lines sub / hit l n i)
  (setq n (strlen sub))
  (foreach l lines
    (setq i 1)
    (while (and (<= (+ i n -1) (strlen l)) (/= sub (substr l i n))) (setq i (1+ i)))
    (if (<= (+ i n -1) (strlen l)) (setq hit T)))
  hit)
(defun t-off-mk (z1 z2 ang ref rtype h st tc)
  (ctr-offset-attach (ctr-offset-from-angle z1 z2 ang) ref rtype h st tc))
(defun t-off-st (res id) (ctr-offset-check-status (ctr-offset-checks res) id))
(defun t-off-chk-lines (res id) (cdr (assoc "LINES" (ctr-offset-find-check (ctr-offset-checks res) id))))

(defun ctr-run-offset-tests (/ r f fa lines e)
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
  (t-check "X4 annotation without elevation model: centre line is NOT printed as tray EL"
    (and (= (nth 0 lines) "SCADA TRAY 300W") (= (nth 1 lines) "B.EL NOT SET") (= (nth 2 lines) "T.EL NOT SET")
         (= (nth 3 lines) "DOWN 600 / 30 deg") (= (nth 4 lines) "RUN=1039 / SLOPE=1200") (= (length lines) 5)))
  (t-check "X5 FITTING reserved but not the active mode"
    (and (member "FITTING" *CTR-OFFSET-MODES*) (= "GEOMETRIC" *CTR-OFFSET-MODE*)))
  (t-check "X6 steep 89.9 deg stays finite" (< (cdr (assoc "HORIZONTAL_RUN" (ctr-offset-from-angle 0.0 600.0 89.9))) 2.0))

  ;; ---- Elevation model: CENTER / BOTTOM / TOP (geometry stays separate) ----
  (princ "\n-- CTOFFSET elevation model + owner warnings --")
  (setq e (ctr-offset-elevations 3000.0 "CENTER" 150.0))
  (t-check "E1 CENTER Z=3000 h=150: bottom 2925 / center 3000 / top 3075"
    (and (t-off-near e "BOTTOM_EL" 2925.0 1e-9) (t-off-near e "CENTER_EL" 3000.0 1e-9) (t-off-near e "TOP_EL" 3075.0 1e-9)))
  (setq e (ctr-offset-elevations 3000.0 "BOTTOM" 150.0))
  (t-check "E2 BOTTOM Z=3000 h=150: bottom 3000 / center 3075 / top 3150"
    (and (t-off-near e "BOTTOM_EL" 3000.0 1e-9) (t-off-near e "CENTER_EL" 3075.0 1e-9) (t-off-near e "TOP_EL" 3150.0 1e-9)))
  (setq e (ctr-offset-elevations 3000.0 "TOP" 150.0))
  (t-check "E3 TOP Z=3000 h=150: top 3000 / center 2925 / bottom 2850"
    (and (t-off-near e "TOP_EL" 3000.0 1e-9) (t-off-near e "CENTER_EL" 2925.0 1e-9) (t-off-near e "BOTTOM_EL" 2850.0 1e-9)))
  (t-check "E4 invalid reference / height / z rejected"
    (and (null (ctr-offset-elevations 3000.0 "MIDDLE" 150.0)) (null (ctr-offset-elevations 3000.0 "CENTER" 0.0))
         (null (ctr-offset-elevations 3000.0 "CENTER" -5.0)) (null (ctr-offset-elevations 3000.0 nil 150.0))
         (null (ctr-offset-elevations nil "CENTER" 150.0)) (null (ctr-offset-elevations 3000.0 "CENTER" nil))))
  (t-check "E4b integer inputs accepted" (t-off-near (ctr-offset-elevations 3000 "CENTER" 150) "BOTTOM_EL" 2925.0 1e-9))
  ;; stored internally as numbers, not only formatted strings
  (setq r (t-off-mk 3300.0 2700.0 30.0 "CENTER" "FLOOR_RELATIVE" 150.0 "SCADA" nil))
  (t-check "E5 all six START/END centre/bottom/top values stored as numbers"
    (and (t-off-near r "START_CENTER_EL" 3300.0 1e-9) (t-off-near r "START_BOTTOM_EL" 3225.0 1e-9) (t-off-near r "START_TOP_EL" 3375.0 1e-9)
         (t-off-near r "END_CENTER_EL" 2700.0 1e-9) (t-off-near r "END_BOTTOM_EL" 2625.0 1e-9) (t-off-near r "END_TOP_EL" 2775.0 1e-9)))
  (t-check "E5b reference / type / height / system stored"
    (and (= "CENTER" (cdr (assoc "ELEVATION_REFERENCE" r))) (= "FLOOR_RELATIVE" (cdr (assoc "REFERENCE_TYPE" r)))
         (t-off-near r "TRAY_HEIGHT" 150.0 1e-9) (= "SCADA" (cdr (assoc "SYSTEM_TYPE" r)))))
  (t-check "E6 geometry unchanged by the elevation model (START_Z/END_Z/DELTA/RUN/SLOPE)"
    (and (t-off-near r "START_Z" 3300.0 1e-9) (t-off-near r "END_Z" 2700.0 1e-9) (t-off-near r "DELTA_Z" -600.0 1e-9)
         (t-off-near r "HORIZONTAL_RUN" 1039.2305 0.0001) (t-off-near r "SLOPE_LENGTH" 1200.0 1e-6)))
  (t-check "E7 attach rejects bad reference type / reference / height / system type / clearance"
    (and (null (t-off-mk 3300.0 2700.0 30.0 "CENTER" "FOO" 150.0 nil nil))
         (null (t-off-mk 3300.0 2700.0 30.0 "MIDDLE" "ABSOLUTE" 150.0 nil nil))
         (null (t-off-mk 3300.0 2700.0 30.0 "CENTER" "ABSOLUTE" 0.0 nil nil))
         (null (t-off-mk 3300.0 2700.0 30.0 "CENTER" "ABSOLUTE" 150.0 "GAS" nil))
         (null (t-off-mk 3300.0 2700.0 30.0 "CENTER" "ABSOLUTE" 150.0 nil "x"))
         (null (ctr-offset-attach nil "CENTER" "ABSOLUTE" 150.0 nil nil))))
  (setq lines (ctr-offset-format-elevation r))
  (t-check "E8 elevation report lines"
    (and (t-off-has-line lines "Elev Reference  : CENTER") (t-off-has-line lines "Reference Type  : FLOOR_RELATIVE")
         (t-off-has-line lines "Tray Height     : 150.00 mm")
         (t-off-has-line lines "Start B/C/T EL  : 3225.00 / 3300.00 / 3375.00 mm")
         (t-off-has-line lines "End B/C/T EL    : 2625.00 / 2700.00 / 2775.00 mm")))
  (t-check "E8b no elevation report without a model" (null (ctr-offset-format-elevation (ctr-offset-from-angle 3300.0 2700.0 30.0))))

  ;; ---- annotation: bottom + top, no invented datum ----
  (setq lines (ctr-offset-annotation r "SCADA TRAY 300W"))
  (t-check "A1 annotation CENTER 3300->2700 h150: B.EL/T.EL two-point, REF type, no +-0.00"
    (and (= (nth 0 lines) "SCADA TRAY 300W") (= (nth 1 lines) "B.EL +3225 -> +2625") (= (nth 2 lines) "T.EL +3375 -> +2775")
         (= (nth 3 lines) "DOWN 600 / 30 deg") (= (nth 4 lines) "RUN=1039 / SLOPE=1200") (= (nth 5 lines) "REF=FLOOR_RELATIVE")
         (not (t-off-has-sub lines "0.00")) (not (t-off-has-sub lines "3300"))))
  (setq lines (ctr-offset-annotation (t-off-mk 3300.0 2700.0 30.0 "BOTTOM" "FLOOR_RELATIVE" 150.0 nil nil) "SCADA TRAY 300W"))
  (t-check "A2 annotation BOTTOM 3300->2700: B.EL +3300 -> +2700 / T.EL +3450 -> +2850"
    (and (= (nth 1 lines) "B.EL +3300 -> +2700") (= (nth 2 lines) "T.EL +3450 -> +2850")))
  (setq lines (ctr-offset-annotation (t-off-mk 3300.0 3300.0 30.0 "BOTTOM" "ABSOLUTE" 150.0 nil nil) "T"))
  (t-check "A3 LEVEL annotation: single B.EL/T.EL, ABSOLUTE ref"
    (and (= (nth 1 lines) "B.EL +3300") (= (nth 2 lines) "T.EL +3450") (= (nth 3 lines) "LEVEL") (= (nth 5 lines) "REF=ABSOLUTE")))

  ;; ---- bottom height (BOTTOM_EL, FLOOR_RELATIVE only) ----
  (t-check "B1 FLOOR_RELATIVE bottom 2499 -> WARNING"
    (= "WARNING" (t-off-st (t-off-mk 2499.0 2499.0 30.0 "BOTTOM" "FLOOR_RELATIVE" 150.0 nil nil) "BOTTOM_HEIGHT")))
  (t-check "B2 FLOOR_RELATIVE bottom 2500 -> no below-height warning (PASS)"
    (= "PASS" (t-off-st (t-off-mk 2500.0 2500.0 30.0 "BOTTOM" "FLOOR_RELATIVE" 150.0 nil nil) "BOTTOM_HEIGHT")))
  (t-check "B3 judged on BOTTOM not CENTER: centre 2574 (>=2500) but bottom 2499 -> WARNING"
    (= "WARNING" (t-off-st (t-off-mk 2574.0 2574.0 30.0 "CENTER" "FLOOR_RELATIVE" 150.0 nil nil) "BOTTOM_HEIGHT")))
  (t-check "B3b centre 2575 -> bottom 2500 -> PASS"
    (= "PASS" (t-off-st (t-off-mk 2575.0 2575.0 30.0 "CENTER" "FLOOR_RELATIVE" 150.0 nil nil) "BOTTOM_HEIGHT")))
  (t-check "B3c TOP reference: top 2649 / bottom 2499 -> WARNING"
    (= "WARNING" (t-off-st (t-off-mk 2649.0 2649.0 30.0 "TOP" "FLOOR_RELATIVE" 150.0 nil nil) "BOTTOM_HEIGHT")))
  (setq r (t-off-mk 2000.0 2000.0 30.0 "BOTTOM" "ABSOLUTE" 150.0 nil nil))
  (t-check "B4 ABSOLUTE bottom 2000: NOT CHECKED, floor level never assumed"
    (and (= "NOT CHECKED" (t-off-st r "BOTTOM_HEIGHT")) (not (= "WARNING" (t-off-st r "BOTTOM_HEIGHT")))
         (t-off-has-sub (t-off-chk-lines r "BOTTOM_HEIGHT") "not FLOOR_RELATIVE")))
  (t-check "B5 offset: either end below 2500 warns (start 3000 ok, end bottom 2400)"
    (= "WARNING" (t-off-st (t-off-mk 3000.0 2400.0 30.0 "BOTTOM" "FLOOR_RELATIVE" 150.0 nil nil) "BOTTOM_HEIGHT")))
  (t-check "B6 bottom check without an elevation model: NOT CHECKED"
    (= "NOT CHECKED" (t-off-st (ctr-offset-from-angle 3000.0 2400.0 30.0) "BOTTOM_HEIGHT")))

  ;; ---- offset angle (warning only; interpretation of the owner term is pending) ----
  (t-check "G1 SCADA 60 deg -> no exceed warning" (= "PASS" (t-off-st (t-off-mk 3300.0 2700.0 60.0 "CENTER" "FLOOR_RELATIVE" 150.0 "SCADA" nil) "OFFSET_ANGLE")))
  (setq r (t-off-mk 3300.0 2700.0 60.01 "CENTER" "FLOOR_RELATIVE" 150.0 "SCADA" nil))
  (t-check "G2 SCADA 60.01 deg -> WARNING with source + Interpretation pending"
    (and (= "WARNING" (t-off-st r "OFFSET_ANGLE"))
         (t-off-has-sub (t-off-chk-lines r "OFFSET_ANGLE") "WARNING: Offset angle exceeds Appendix C weak-current guidance of 60 deg.")
         (t-off-has-sub (t-off-chk-lines r "OFFSET_ANGLE") "Source: Appendix C")
         (t-off-has-sub (t-off-chk-lines r "OFFSET_ANGLE") "Interpretation pending")))
  (t-check "G3 LOW_CURRENT 60 ok / 60.01 warns (same limit as SCADA)"
    (and (= "PASS" (t-off-st (t-off-mk 3300.0 2700.0 60.0 "CENTER" "FLOOR_RELATIVE" 150.0 "LOW_CURRENT" nil) "OFFSET_ANGLE"))
         (= "WARNING" (t-off-st (t-off-mk 3300.0 2700.0 60.01 "CENTER" "FLOOR_RELATIVE" 150.0 "LOW_CURRENT" nil) "OFFSET_ANGLE"))))
  (t-check "G4 POWER 45 deg -> no exceed warning" (= "PASS" (t-off-st (t-off-mk 3300.0 2700.0 45.0 "CENTER" "FLOOR_RELATIVE" 150.0 "POWER" nil) "OFFSET_ANGLE")))
  (setq r (t-off-mk 3300.0 2700.0 45.01 "CENTER" "FLOOR_RELATIVE" 150.0 "POWER" nil))
  (t-check "G5 POWER 45.01 deg -> WARNING, power-cable + Interpretation pending"
    (and (= "WARNING" (t-off-st r "OFFSET_ANGLE"))
         (t-off-has-sub (t-off-chk-lines r "OFFSET_ANGLE") "WARNING: Offset angle exceeds Appendix C power-cable guidance of 45 deg.")
         (t-off-has-sub (t-off-chk-lines r "OFFSET_ANGLE") "Interpretation pending")))
  (t-check "G6 POWER 50 deg warns but SCADA 50 deg does not (per system type)"
    (and (= "WARNING" (t-off-st (t-off-mk 3300.0 2700.0 50.0 "CENTER" "FLOOR_RELATIVE" 150.0 "POWER" nil) "OFFSET_ANGLE"))
         (= "PASS" (t-off-st (t-off-mk 3300.0 2700.0 50.0 "CENTER" "FLOOR_RELATIVE" 150.0 "SCADA" nil) "OFFSET_ANGLE"))))
  (t-check "G7 no system type -> NOT CHECKED; LEVEL -> N/A"
    (and (= "NOT CHECKED" (t-off-st (t-off-mk 3300.0 2700.0 80.0 "CENTER" "FLOOR_RELATIVE" 150.0 nil nil) "OFFSET_ANGLE"))
         (= "N/A" (t-off-st (t-off-mk 3000.0 3000.0 80.0 "CENTER" "FLOOR_RELATIVE" 150.0 "POWER" nil) "OFFSET_ANGLE"))))
  (t-check "G8 warning never changes geometry or blocks the result (angle 80 still computed)"
    (t-off-near (t-off-mk 3300.0 2700.0 80.0 "CENTER" "FLOOR_RELATIVE" 150.0 "POWER" nil) "ANGLE_DEG" 80.0 1e-9))

  ;; ---- top clearance (user-supplied only; slab level never guessed) ----
  (t-check "H1 top clearance 300 -> PASS" (= "PASS" (t-off-st (t-off-mk 3300.0 2700.0 30.0 "CENTER" "FLOOR_RELATIVE" 150.0 nil 300.0) "TOP_CLEARANCE")))
  (setq r (t-off-mk 3300.0 2700.0 30.0 "CENTER" "FLOOR_RELATIVE" 150.0 nil 299.0))
  (t-check "H2 top clearance 299 -> WARNING difficult condition"
    (and (= "WARNING" (t-off-st r "TOP_CLEARANCE")) (t-off-has-sub (t-off-chk-lines r "TOP_CLEARANCE") "difficult-condition")))
  (setq r (t-off-mk 3300.0 2700.0 30.0 "CENTER" "FLOOR_RELATIVE" 150.0 nil 150.0))
  (t-check "H3 top clearance 150 -> WARNING difficult condition (not below minimum)"
    (and (= "WARNING" (t-off-st r "TOP_CLEARANCE")) (t-off-has-sub (t-off-chk-lines r "TOP_CLEARANCE") "difficult-condition")
         (not (t-off-has-sub (t-off-chk-lines r "TOP_CLEARANCE") "below the Appendix C minimum"))))
  (setq r (t-off-mk 3300.0 2700.0 30.0 "CENTER" "FLOOR_RELATIVE" 150.0 nil 149.0))
  (t-check "H4 top clearance 149 -> WARNING below minimum"
    (and (= "WARNING" (t-off-st r "TOP_CLEARANCE")) (t-off-has-sub (t-off-chk-lines r "TOP_CLEARANCE") "below the Appendix C minimum of 150 mm")))
  (t-check "H5 no TOP_CLEARANCE -> NOT CHECKED (nothing inferred)"
    (= "NOT CHECKED" (t-off-st (t-off-mk 3300.0 2700.0 30.0 "CENTER" "FLOOR_RELATIVE" 150.0 nil nil) "TOP_CLEARANCE")))

  ;; ---- cable bending radius: reported as unverified, never judged ----
  (setq r (t-off-mk 3300.0 2700.0 30.0 "CENTER" "FLOOR_RELATIVE" 150.0 "SCADA" nil))
  (t-check "K1 offset present -> CABLE_BEND_RADIUS_CHECK NOT CHECKED + WARNING text"
    (and (= "NOT CHECKED" (t-off-st r "CABLE_BEND_RADIUS_CHECK"))
         (t-off-has-sub (t-off-chk-lines r "CABLE_BEND_RADIUS_CHECK") "WARNING: Cable minimum bending radius has not been verified.")))
  (t-check "K2 LEVEL -> no cable-bend warning text"
    (not (t-off-has-sub (t-off-chk-lines (t-off-mk 3000.0 3000.0 30.0 "CENTER" "FLOOR_RELATIVE" 150.0 "SCADA" nil) "CABLE_BEND_RADIUS_CHECK") "WARNING")))
  (setq lines (ctr-offset-format-checks (ctr-offset-checks r)))
  (t-check "K3 checks report lists all four checks"
    (and (t-off-has-sub lines "OFFSET_ANGLE") (t-off-has-sub lines "BOTTOM_HEIGHT")
         (t-off-has-sub lines "TOP_CLEARANCE") (t-off-has-sub lines "CABLE_BEND_RADIUS_CHECK")))

  ;; ---- ELBOW 0.3 m inner bend radius: validation record only, geometry untouched ----
  (t-check "R1 ELBOW inner radius record: owner min 300, candidate 264.5, mapping unconfirmed, status UNVERIFIED (not FAIL)"
    (and (= "ELBOW_INNER_RADIUS_REQUIRES_VERIFICATION" (cdr (assoc "ID" *CTR-ELBOW-INNER-RADIUS-RECORD*)))
         (t-near 300.0 (cdr (assoc "OWNER_MIN" *CTR-ELBOW-INNER-RADIUS-RECORD*)))
         (t-near 264.5 (cdr (assoc "MEASURED_CANDIDATE" *CTR-ELBOW-INNER-RADIUS-RECORD*)))
         (= "UNCONFIRMED" (cdr (assoc "BLOCK_WIDTH_MAPPING" *CTR-ELBOW-INNER-RADIUS-RECORD*)))
         (= "UNVERIFIED" (cdr (assoc "STATUS" *CTR-ELBOW-INNER-RADIUS-RECORD*)))))
  (princ)
  *T-FAIL*)

(princ "\nctr offset tests loaded: run (ctr-run-offset-tests)")
(princ)
