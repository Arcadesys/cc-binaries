# Physics calibration

The physics are an arcade-scale rigid-contact model in meters. A delivery advances at 1/120 second, with collision substeps limiting ball travel to about 3.5 cm. The ball is a sphere; each pin is a capsule whose centerline rotates from upright to lying. Ball-pin and pin-pin contacts use relative velocity at the closest points, restitution, linear impulse, and pin angular impulse. A contact latch prevents repeated impulses while two bodies remain overlapped. Down pins remain colliders until they settle. Static overlaps do not add energy.

Coefficients are intentionally tuned for readable play rather than regulation bowling: ball mass 6.8 kg, pin mass 1.6 kg, pin inertia 0.073 kg m², contact restitution 1.08 for ball-pin and 1.05 for pin-pin, rolling deceleration 0.15 m/s², hook acceleration 0.6 m/s² at full hook after the approach fraction grows downlane, and pin angular damping/gravity in `lib/physics.lua`. Ball speed is `3.8 + 7.7 * power` m/s. The capped 12-second simulation and 120 fixed steps per advance call bound work and provide a cancellable result.

The current repeatable fixtures use a fresh rack, aim in radians, hook in `[-1,1]`, and position in meters:

| Fixture | First delivery | Second delivery | Observed result |
|---|---|---|---|
| Strike | position `-0.08`, aim `0`, power `1.00`, hook `0` | — | All ten pins fall through contacts and pin-pin transfers. |
| Partial then spare | position `0.27`, aim `0`, power `0.80`, hook `0` | From the returned standing poses: position `-0.38`, aim `0`, power `0.40`, hook `0` | First delivery knocks six; second knocks all four survivors. |
| Hook direction | position `0`, aim `0`, power `0.75`, hook `+1` or `-1` | — | On an empty lane, positive hook ends farther toward `+Z` than negative hook. |
| Gutter lockout | position `0.38`, aim `0`, power `1.00`, hook `+1` | — | Ball enters the right gutter before the rack and cannot re-enter or knock pins. |

These fixtures are asserted by `tests/physics.lua`; the two-shot test passes the first result's actual `standing` poses into the second simulation. The model preserves those poses, and no result is assigned from a hardcoded pin count.

## Terminal presentation scale

Physics stays in meters. The renderer stretches the lane and object positions across Z by 3× so the 1.0541 m lane occupies enough character cells to read. It does not stretch object meshes: the ball remains spherical and upright pins keep circular footprints. The ball is drawn 1.6× its collision diameter and raised to rest visually on the lane; pins are drawn 1.8× their collision geometry in the distant lane camera and 1.3× in the close deck camera. These are display choices only. Facet shading and a closed pin crown make volume visible at 39×19. The numbered diagram reports exact simulation knockdown state. The lane camera stops advancing beyond X=11.5 m as the ball nears the rack so the settled rack remains in view after a delivery.
