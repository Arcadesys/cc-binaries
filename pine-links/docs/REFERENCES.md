# Hole 7 source notes

This is an unofficial, low-poly game recreation. Geometry is authored for play and is not surveyed Pebble Beach terrain.

## Source evidence

- **R9 — 2026 official Blue tee scorecard.** The course manifest records hole 7 as par 3, 107 yards. The scorecard is the numeric authority for this data. [Official scorecard PDF](https://www.pebblebeach.com/content/uploads/PebbleBeach-Scorecard.pdf)
- **R10 — Official course page.** Hole 7 is described as a 107-yard par 3. The page advises using the flag on the sixth green to judge wind. [Pebble Beach Golf Links](https://www.pebblebeach.com/golf/pebble-beach-golf-links/)
- **R11 — Official historical photo essay.** Jack Neville's 1917 description says the hole drops 40 feet from tee to green and the green is surrounded on three sides by the bay. The essay documents changes to the green and surrounding bunkers across eras. Its text notes a 106-yard historical PGA Tour figure; that does not replace R9's selected Blue tee value. [The 7th Hole at Pebble Beach: From Unfit to Unforgettable](https://www.pebblebeach.com/insidepebblebeach/a-history-of-the-7th-hole-at-pebble-beach-in-photos/)
- **Current official photo used for visual review:** [7th green and approach view](https://www.pebblebeach.com/content/uploads/PBGL_Thursday-TaylorMade_11-17-16_KM-016.jpg). The visible green is compact and close to the water, with sand flanking the green and a steep grassy slope behind it. This is an oblique current view, not an overhead survey.

## Authored assumptions

The coordinate frame uses yards, tee `(0,0)`, cup `(107,0)`, x toward the green and z across the hole. The straight tee-to-cup distance is set to the selected listed yardage. Tee elevation is 13.3 yards, a direct unit conversion of the essay's approximate 40-foot historical drop; the current source describes the height change as a drop from tee to green. The modeled green spans approximately x=98–110 yards, with a 12-yard-deep target and an inferred cup 9 yards from its front and 3 yards from its back. This provides an explicit playable target for wedge carry calibration; neither pin nor green dimensions are measured from a survey. Intermediate slopes, peninsula outline, bunker footprints, playable boundaries, and exact coastline are authored approximations. The simple wedge-shaped peninsula represents the three-sided bay context; it does not reproduce surveyed coastline geometry.

`courses/pebble_beach/hole_07.json` is the source data. `tools/preview_course.py` generates both the runtime Lua table (`hole_07.lua`) and the review SVG, so runtime and preview geometry come from one triangle array. `lib/course.lua` is pure Lua and loads that table by module name. Triangles use upward-facing winding for renderer backface culling and each has exactly one material tag (`rough`, `fairway`, `green`, or `bunker`), so render and collision surfaces share the same boundaries. There is no ground mesh beneath the water or beyond the shoreline. Water level is an authored hazard value. The green and bunkers are not separate overlay meshes.

The review drawing is generated from the same triangle array by `tools/preview_course.py`; labels distinguish verified scorecard values from inferred geometry. It is a top-down data review, not a map supplied by Pebble Beach.
