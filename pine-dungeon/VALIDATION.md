# Pine Dungeon validation

The game has three reachable authored floors. Unit checks cover combat, monster turns, healing, gold and potion pickup, stairs, victory/death, pause/help state, foreign-touch filtering, minimum button sizes, and Pine3D drawing at 39×19 and 51×19. A route driven only through ordinary world actions wins the full campaign.

The GUI integration runner drives the actual application dispatcher with queued keyboard or monitor-touch events. Both modes finish the three-floor campaign in 42 turns with 8 HP remaining and 5 gold. The monitor run also shrinks below the supported display size, restores the monitor, detaches it, resumes on the terminal, and exits with the original terminal palette restored. Actual timing results and screenshots are in the companion output bundle.

The installed CraftOS-PC application was inspected at 51×19 and in an exact 39×19 window. The first-person corridor, persistent full ASCII floor map, enlarged map, movement, and two-row tap targets were visually reviewed.

On the final GUI integration run, the keyboard campaign drew 49 frames at a mean of 0.57 ms per frame (maximum 1 ms). The monitor campaign drew 53 frames at a mean of 0.66 ms (maximum 5 ms). These are CraftOS-PC `os.epoch` measurements of the draw call, not Minecraft frame timings.

Minecraft/ATM10 and physical Advanced Monitor validation remain separate gates.
