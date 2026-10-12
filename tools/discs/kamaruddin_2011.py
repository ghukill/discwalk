"""Measured golf-disc aerodynamics from Kamaruddin (2011).

N. M. Kamaruddin, "Dynamics and Performance of Flying Discs", PhD thesis,
University of Manchester, 2011.
https://pure.manchester.ac.uk/ws/portalfiles/portal/54511821/FULL_TEXT.PDF

Wind-tunnel loads on NON-spinning commercial golf discs (spin barely changes
the loads: Potts 2005), angle of attack -5..15 deg in 1 deg steps, Reynolds
number 3.78e5 (22-27 m/s, i.e. real throwing speeds). Pitching moment is about
the half-chord point = the disc centre. Measured side force and rolling moment
were ~0 (Fig. 5.12 e/f).

What is here, and how we got it (these are facts measured by Kamaruddin; the
numbers below are our reading of them):

- GEOMETRY: Table 4.1, typed in. (No entry for "Storm".)
- LINEAR FITS: Table 5.6, typed in. CL_0, dCL/da (per deg), CD_0, CM_0,
  dCM/da (per deg), trim angle (deg).
- AERODYNAMIC CENTRE: Table 5.7, typed in: % of chord AHEAD of the half chord.
- CURVES: digitized by eye (Henon, 2026-10-11) from the thesis figures,
  rendered at 400 dpi with a 1 deg x 0.01 grid overlaid; reading precision
  about +-0.003 (CM) and +-0.005 (CD). Sources:
    Aviar CM, CD .......... Fig. 5.10 (c), (b)   (alone with flat plate + Frisbee)
    Roc CM, CD ............ Fig. 5.9 (d), (b)    ("mid-range"; Aviar/Roc/Wraith
                                                  are the typical discs, see
                                                  Kamaruddin, Potts & Crowther 2018)
    Wraith CD ............. Fig. 5.9 (b)         ("driver")
    Wraith/Flick/Storm/QK CM Fig. 5.11 (c)
    Buzz CM ............... Fig. 5.12 (c)        (crowded: +-0.005; agrees with
                                                  Table 5.6, trim 8 deg)
  Not digitized (curves overlap within reading precision), so built in
  build_tables.py from the digitized ones plus Table 5.6:
    Buzz CD: Roc's curve shifted by the CD_0 difference.
    Flick/Storm/Quarter K CD: Wraith's curve shifted by the CD_0 difference at
    low alpha, tapering to the difference read at 15 deg.
  CL is linear over -5..15 for every disc (Figs. 5.9-5.12 a), so CL uses the
  Table 5.6 fit.
"""

ALPHA = list(range(-5, 16))  # deg, the measured points

# Table 4.1: diameter, thickness, inside rim diameter, rim width, rim depth (m)
GEOMETRY = {
    "Aviar":    dict(maker="Innova", kind="putter",    d=0.212, t=0.020, d_in=0.194, rim_w=0.009, rim_h=0.015),
    "Roc":      dict(maker="Innova", kind="mid-range", d=0.212, t=0.020, d_in=0.194, rim_w=0.009, rim_h=0.012),
    "Buzz":     dict(maker="Discraft", kind="mid-range", d=0.217, t=0.019, d_in=0.193, rim_w=0.012, rim_h=0.013),
    "Wraith":   dict(maker="Innova", kind="driver",    d=0.211, t=0.014, d_in=0.169, rim_w=0.021, rim_h=0.012),
    "Flick":    dict(maker="Discraft", kind="driver",  d=0.211, t=0.013, d_in=0.169, rim_w=0.021, rim_h=0.011),
    "Quarter K": dict(maker="Discwing", kind="driver", d=0.213, t=0.020, d_in=0.167, rim_w=0.023, rim_h=0.014),
}

# Table 5.6: CL_0, dCL/da (/deg), CD_0, CM_0, dCM/da (/deg), trim (deg)
FITS = {
    "Aviar":     (0.152, 0.044, 0.083, -0.018, 0.002, 8),
    "Buzz":      (0.099, 0.041, 0.061, -0.033, 0.004, 8),
    "Roc":       (0.053, 0.043, 0.067, -0.015, 0.003, 8),
    "Flick":     (0.100, 0.038, 0.076, -0.007, 0.008, 1),
    "Storm":     (0.107, 0.045, 0.057, -0.026, 0.004, 7),
    "Wraith":    (0.143, 0.040, 0.055, -0.020, 0.006, 4),
    "Quarter K": (0.138, 0.039, 0.065, -0.038, 0.005, 7),
}

# Table 5.7: aerodynamic centre, fraction of the chord (= diameter) ahead of centre
AERO_CENTRE = {"Aviar": 0.05, "Roc": 0.07, "Buzz": 0.10, "Storm": 0.09,
               "Quarter K": 0.13, "Wraith": 0.15, "Flick": 0.21}

# Digitized pitching moment C_M at ALPHA (-5..15)
CM = {
    "Aviar":  [-0.016, -0.017, -0.013, -0.011, -0.014, -0.018, -0.018, -0.018, -0.016, -0.016,
               -0.012, -0.009, -0.005, -0.001, 0.004, 0.009, 0.011, 0.020, 0.024, 0.032, 0.039],
    "Roc":    [-0.030, -0.025, -0.023, -0.018, -0.016, -0.014, -0.012, -0.011, -0.009, -0.008,
               -0.005, -0.003, -0.002, -0.001, 0.005, 0.010, 0.016, 0.024, 0.028, 0.034, 0.040],
    "Buzz":   [-0.042, -0.040, -0.038, -0.036, -0.034, -0.0335, -0.032, -0.031, -0.028, -0.026,
               -0.020, -0.012, -0.006, 0.000, 0.007, 0.012, 0.022, 0.026, 0.036, 0.044, 0.049],
    "Wraith": [-0.060, -0.046, -0.039, -0.035, -0.025, -0.020, -0.016, -0.009, -0.004, 0.001,
               0.009, 0.018, 0.020, 0.025, 0.031, 0.038, 0.049, 0.056, 0.064, 0.071, 0.080],
    "Flick":  [-0.060, -0.039, -0.034, -0.019, -0.013, -0.007, 0.005, 0.004, 0.009, 0.015,
               0.025, 0.032, 0.042, 0.047, 0.057, 0.067, 0.080, 0.090, 0.102, 0.113, 0.118],
    "Storm":  [-0.032, -0.030, -0.025, -0.023, -0.025, -0.026, -0.019, -0.019, -0.015, -0.010,
               -0.012, -0.006, 0.001, 0.005, 0.014, 0.022, 0.032, 0.041, 0.048, 0.058, 0.060],
    "Quarter K": [-0.060, -0.054, -0.051, -0.046, -0.040, -0.038, -0.033, -0.027, -0.023, -0.017,
                  -0.015, -0.006, 0.003, 0.005, 0.010, 0.018, 0.029, 0.037, 0.043, 0.051, 0.060],
}

# Digitized drag C_D at ALPHA (-5..15)
CD = {
    "Aviar":  [0.076, 0.070, 0.069, 0.072, 0.072, 0.084, 0.087, 0.085, 0.102, 0.117,
               0.134, 0.140, 0.157, 0.173, 0.189, 0.203, 0.216, 0.226, 0.245, 0.266, 0.282],
    "Roc":    [0.076, 0.073, 0.067, 0.065, 0.064, 0.068, 0.074, 0.076, 0.084, 0.095,
               0.099, 0.109, 0.125, 0.129, 0.144, 0.159, 0.170, 0.186, 0.199, 0.214, 0.234],
    "Wraith": [0.058, 0.052, 0.051, 0.050, 0.050, 0.056, 0.060, 0.062, 0.071, 0.075,
               0.084, 0.089, 0.103, 0.118, 0.126, 0.141, 0.153, 0.167, 0.185, 0.197, 0.220],
}

# C_D read at 15 deg for the drivers not digitized in full (Fig. 5.11 b)
CD15 = {"Flick": 0.235, "Storm": 0.227, "Quarter K": 0.231}
