# ComputerCraft Personal OS

## Pine Dungeon

The separate [`pine-dungeon`](pine-dungeon/README.md) program is a compact first-person Pine3D dungeon crawler with a persistent ASCII map, three floors, turn-based monsters, loot, keyboard controls, and Advanced Monitor tap targets.

## Pine Ball

The separate [`pine-ball`](pine-ball/README.md) program is Pine3D arcade baseball at Rogers Bark Municipal Field, running the furball-simulator baseball engine against a CPU pitcher or a second player.

## Pine Lanes

The separate [`pine-lanes`](pine-lanes/README.md) program adds local multiplayer bowling with Pine3D on the furball-simulator bowling engine: approach position, launch angle, power and spin, collision-driven pin action, and ten-frame scoring. Keyboard and Advanced Monitor tap controls are supported.

## Pine Links

The separate [`pine-links`](pine-links/README.md) program adds Pine3D golf on furball-simulator's Marovitz-inspired Hole 3, using the furball golf engine with a shot forecast. It includes keyboard and Advanced Monitor controls, parity, physics and scoring tests, and a display/input diagnostic. The existing desktop and MIDI programs remain separate entry points.

This is a simple GUI-based operating system for ComputerCraft, styled after early Windows systems (Windows 95/98).

## Features

- **Desktop Environment**: Classic cyan background.
- **Taskbar**: Located at the bottom with a Start button.
- **Window Management**:
  - Drag windows by the title bar.
  - Close windows with the 'X' button.
  - Click a window to bring it to the front.
- **Start Menu**: Click "Start" to open. Includes a "Shutdown" option.
- **Sequencer**: A built-in 4-track, 16-step sequencer.
  - Each track can target any vanilla note block instrument.
  - Select steps to adjust pitch (0-24) and note length (1-8 steps).
  - Click steps to toggle them on/off; right-click to select without toggling.
  - Plays through an attached speaker peripheral with per-step indicators.
- **MIDI Player** (`midi_player.lua`): Standalone program that parses standard `.mid` files.
  - Place MIDI files under `/midi` (folders are created automatically on first run).
  - Choose a file interactively or pass the path/filename as the first argument.
  - Pick the ComputerCraft instrument for every detected MIDI channel before playback.
  - Supports looping playback via `--loop` or a prompt.

## Installation

1. Copy the `startup.lua` file to the root of your ComputerCraft computer.
2. (Optional) Copy `midi_player.lua` alongside `startup.lua` to enable MIDI playback.
3. Reboot the computer.

## Usage

- **Mouse**: Use the mouse to interact with windows and menus.
- **Shutdown**: Open the Start menu and click "Shutdown" (or the area where it would be).
- **MIDI Player**: Run `midi_player` from the shell. Follow the prompts to select a `.mid` file, map instruments, and choose whether to loop.

## Development

The main logic is in `startup.lua`.

- `windows` table: Defines the initial windows.
- `draw()`: Handles rendering.
- `handleClick()`: Handles mouse interaction.

`midi_player.lua` is a separate script with its own entry point. It includes a lightweight SMF (Standard MIDI File) parser and playback loop for speaker peripherals.
