# TurtleOS APIs

This directory contains ComputerCraft API modules for TurtleOS.

## Movement API

A state machine-based movement system for tracking turtle position, orientation, and handling intelligent movement with retry logic.

### Loading the API

```lua
os.loadAPI("turtleos/apis/movement.lua")
```

### Usage Examples

```lua
-- Basic movement
movement.forward(true)  -- Move forward, force through obstacles
movement.up(false)      -- Move up without forcing
movement.turnRight()
movement.turnLeft()

-- Position tracking
local pos = movement.getPosition()
print("Position:", pos.x, pos.y, pos.z)
print("Facing:", movement.getFacing())  -- 0=North, 1=East, 2=South, 3=West

-- Pathfinding
movement.gotoPosition(10, 5, -3, true)  -- Go to coordinates (10, 5, -3)
movement.home(true)                      -- Return to origin (0, 0, 0)

-- State management
print("Current state:", movement.getState())
movement.saveState("my_position.txt")
movement.loadState("my_position.txt")

-- Configuration
movement.configure({
    moveAttempts = 5,      -- Retry failed movements 5 times
    fuelThreshold = 200    -- Warn when fuel < 200
})

-- Fuel management
if not movement.checkFuel() then
    movement.refuel(64)
end

-- Utility
local distance = movement.distanceTo(10, 5, -3)
print("Distance to target:", distance)
```

### API Functions

#### Movement
- `forward(force)` - Move forward, optionally breaking blocks
- `back()` - Move backward
- `up(force)` - Move up, optionally breaking blocks
- `down(force)` - Move down, optionally breaking blocks
- `turnRight()` - Turn 90° clockwise
- `turnLeft()` - Turn 90° counter-clockwise
- `turnAround()` - Turn 180°
- `face(direction)` - Face a specific direction (0-3)

#### Navigation
- `gotoPosition(x, y, z, force)` - Navigate to coordinates
- `home(force)` - Return to origin (0, 0, 0)
- `distanceTo(x, y, z)` - Calculate Manhattan distance

#### State Management
- `getPosition()` - Get current {x, y, z} coordinates
- `getFacing()` - Get current facing direction (0-3)
- `getState()` - Get current state (idle, moving, blocked, etc.)
- `setPosition(x, y, z)` - Manually set position
- `setFacing(direction)` - Manually set facing
- `reset()` - Reset to origin

#### Fuel
- `checkFuel()` - Check if fuel is above threshold
- `refuel(amount)` - Attempt to refuel from inventory

#### Configuration
- `configure(config)` - Set moveAttempts and fuelThreshold
- `saveState(filename)` - Save position/facing to file
- `loadState(filename)` - Load position/facing from file

### States

The movement API tracks these states:
- `idle` - Not currently moving
- `moving` - In motion
- `blocked` - Path is blocked
- `attacking` - Clearing hostile mobs
- `low_fuel` - Fuel below threshold
