# Design references and approximation boundary

- [USBC equipment specifications, March 2026](https://images.bowl.com/bowl/media/assets/usbc/equipment%20specs/26_231-26-march-es-manual.pdf): the foul line to head-pin center is nominally 60 feet (18.288 m), lane width lies between 41 and 42 inches, and adjacent pin spots are nominally 12 inches apart (0.3048 m). The authored lane uses the midpoint width, 41.5 inches (1.0541 m), and equilateral pin rows.
- [USBC Keeping Score](https://bowl.com/welcome/keeping-score-7c992ab8f438aa57fac9f9aef753ae44): ten frames, strike and spare bonuses, unresolved scores until bonus deliveries, and the mixed 150-point reference game.
- [USBC high school rules guide](https://bowl.com/getmedia/004237d3-3d9a-4f03-8cf2-91c916df8d79/hsguide.pdf): standard ten-pin definitions and bonus deliveries.
- [Pine3D](https://github.com/Xella37/Pine3D): actual pinned renderer and its `betterblittle.lua` dependency copied from the already validated Pine Links bundle. Full MIT license retained.
- [CraftOS-PC peripheral emulation](https://www.craftos-pc.cc/docs/periphemu): emulator monitor testing. Its text-scale changes do not emit a resize event in the installed version; the application also checks dimensions on its timer.

The lane proportions and scoring follow the references. Ball speed, friction, restitution, hook force, toppling model, contact approximations, and pit behavior are authored arcade choices documented in CALIBRATION.md. The game does not claim certified lane/equipment physics. Falling pin capsules approximate the occupied space of the visible pin; no score comes from rendering or random pin-count selection.
