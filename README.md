# Plane Construct

A Scrap Mechanic 1.0 Blocks and Parts mod containing aircraft parts and several scripted interactables.

The part uses the vanilla horn model. While its logic input is active, it fires the same `projectile_foam` projectile and muzzle effect used by the handheld fire extinguisher.

## Install for local testing

1. Open the Scrap Mechanic Mod Tool and create a **Blocks and Parts** mod named `Plane Construct`.
2. Close the Mod Tool.
3. Replace the contents of the newly created mod folder with the contents of this folder.
4. Reopen the Mod Tool so it compiles the mod cache.
5. Enable the mod when creating or editing a world.

Connect any logic source to the part. It sprays while the input remains active and stops when the input turns off.

## Plane Controller

The 1x1x1 sensor-shaped plane controller follows the controlling player's line of sight and drives bearing-connected aircraft control surfaces. Point its sensor lens in the aircraft's neutral forward direction. Paint bearings red for ailerons, blue for elevators, yellow for rudders, or purple for elevons. The controller works only while an occupied driver seat is connected; without an occupied seat, every connected bearing is locked at zero degrees. A/D commands roll and W/S commands pitch; pressing any of those keys temporarily disables camera commands. An active logic input painted white also disables camera commands. An active logic input painted black overrides camera, white logic, and WASD commands and levels aircraft roll and pitch against the world horizon while preserving axis offsets. An active logic input painted blue rotates white bearings to the Flaps angle configured in the controller menu; inactive blue logic returns them to zero degrees. The controller provides a standard logic output whenever measured acceleration exceeds 650 blocks per second squared. When Track player is enabled, Distance activation can replace that output with a basic logic signal whenever the selected target is within the configured 0-200 block distance. Tracking PoV is enabled by default and can be disabled independently of Track player; when disabled, the configured PoV does not filter targets. Interact with the controller to change the default 25-degree limit, sensitivity level, axis offsets, damping, Flaps angle, and distance activation range. Sensitivity levels 1-10 scale camera movement by 0.25, 0.5, 1, 2, 4, 6, 8, 10, 12, and 14. Roll, pitch, and yaw offsets each range from -90 to +90 degrees and shift the center after camera movement is limited, so offsets can exceed the Degrees limit value. Damping level 0 is off. Levels 1-20 use `x / (linearSpeed + x)`, with x values 500, 450, 400, 350, 300, 250, 200, 150, 100, 50, 45, 40, 35, 30, 25, 20, 15, 10, 5, and 1. Camera pitch/yaw errors are corrected for creation roll using the same world-error rotation principle as the controller orientation correction. Bearing direction is reversed normally with the Connect Tool.

## Random Output Gate

The green 1x1x1 logic-gate block sends a one-tick pulse to one randomly selected connected logic output. A rising input always fires immediately, while a held input repeats at the interval selected in its interaction menu. The interval is configurable from 0 to 2400 fixed ticks (0 to 60 seconds).

## Fire Detector Gate

The red 1x1x1 vanilla logic-gate block emits a logic signal while any burning shape is within its configured radius. Interact with the block to set the detection radius from 1 to 50 blocks.

## Open source

Plane Construct is distributed under the GNU General Public License, version 3.0. See [LICENSE](LICENSE).

The repository contains source code, data files, models, effects, translations, and icons used by the mod. Generated game caches and local backups are intentionally excluded.

## Credits

- Hex: Low IQ (67) — third-party model assets used with permission under GPLv3.
- New Legend Mod — geometry used by selected blocks; the original author and license remain credited with the imported assets.
