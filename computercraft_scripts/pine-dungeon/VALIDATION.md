# Pine Dungeon validation

The game has three reachable authored floors. Unit checks cover combat, monster turns, healing, gold and potion pickup, stairs, victory/death, pause/help state, foreign-touch filtering, minimum button sizes, and Pine3D drawing at 39×19 and 51×19. A route driven only through ordinary world actions wins the full campaign.

The GUI integration runner drives the actual application dispatcher with queued keyboard or monitor-touch events. With relative movement, both modes finish the three-floor campaign in 55 turns with 4 HP remaining and 5 gold. The monitor run also shrinks below the supported display size, restores the monitor, detaches it, resumes on the terminal, and exits with the original terminal palette restored. Actual timing results and screenshots are in the companion output bundle.

The installed CraftOS-PC application was inspected at 51×19 and in an exact 39×19 window. The first-person corridor, persistent full ASCII floor map, enlarged map, forward/backward movement, turn-in-place, and two-row tap targets were visually reviewed.

On the relative-control GUI integration run, the keyboard and monitor campaigns drew frames in the installed CraftOS-PC. The companion output bundle records their `os.epoch` draw-call measurements; these are not Minecraft frame timings.

Minecraft/ATM10 and physical Advanced Monitor validation remain separate gates.
