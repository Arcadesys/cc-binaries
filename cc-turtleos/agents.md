# TurtleOS Agent Guide

This document provides an overview of the TurtleOS architecture, intended use cases, and schema definitions to assist with future agentic development.

## 1. Project Overview

TurtleOS is a modular operating system designed for ComputerCraft Turtles. It allows turtles to be dynamically configured with specific "Roles" and "Strategies" via a JSON schema, making them adaptable to various tasks without rewriting core code.

## 2. Directory Structure

The codebase is organized as follows:

- **`turtleos/`**: The main application directory.
  - **`lib/`**: Core libraries and utilities.
    - `core.lua`: Main initialization logic.
    - `schema.lua`: Handles loading and parsing of the JSON configuration.
    - `logger.lua`: Logging utility.
  - **`roles/`**: Defines high-level job types. Each file corresponds to a `role` in the schema.
    - Example: `farmer.lua`, `miner.lua`.
  - **`strategies/`**: specific implementations for roles. Organized by role name.
    - Example: `strategies/farmer/potato.lua` (Strategy for the Farmer role).

- **Root Files**:
  - `turtle_schema.json`: The configuration file that dictates the turtle's behavior.
  - `boot.lua` / `startup.lua`: Entry point that loads `turtleos.lib.core`.
  - `install.lua`: Installer script.

## 3. Schema Explanation

The behavior of a turtle is defined by `turtle_schema.json`. This file is loaded at startup.

### JSON Structure

```json
{
    "name": "Turtle Name",
    "version": "1.0.0",
    "role": "role_name",
    "strategy": "strategy_name"
}
```

### Fields

- **`name`** (string): A human-readable name for the turtle or configuration.
- **`version`** (string): Version of the configuration.
- **`role`** (string): The high-level job the turtle performs.
  - **Mapping**: This value maps directly to a file in `turtleos/roles/`.
  - **Example**: `"role": "farmer"` loads `turtleos/roles/farmer.lua`.
- **`strategy`** (string): The specific method the role should execute.
  - **Mapping**: This value maps to a file in `turtleos/strategies/<role>/`.
  - **Example**: `"strategy": "potato"` (with role "farmer") loads `turtleos/strategies/farmer/potato.lua`.

## 4. Intended Use Cases & Workflows

### Adding a New Capability

When asked to add new functionality, determine if it fits an existing **Role** or requires a new one.

1.  **New Strategy for Existing Role**:
    *   If the task is a variation of an existing job (e.g., farming carrots instead of potatoes), create a new strategy file in `turtleos/strategies/<role>/<new_strategy>.lua`.
    *   Update `turtle_schema.json` to test.

2.  **New Role**:
    *   If the task is fundamentally different (e.g., "Guard" or "Crafter"), create a new role file in `turtleos/roles/<new_role>.lua`.
    *   Create a corresponding directory `turtleos/strategies/<new_role>/`.
    *   Implement at least one strategy for the new role.

### Modifying Behavior

*   **Logic Changes**: Edit the specific strategy file (e.g., `turtleos/strategies/farmer/potato.lua`) to change how the task is performed.
*   **Core Changes**: Edit `turtleos/lib/` files only for system-wide changes (logging, error handling, schema parsing).

## 5. Key Implementation Details

- **Role Interface**: A role module must return a table with a `run(schema)` function.
- **Strategy Interface**: A strategy module must return a table with an `execute()` function (or whatever the specific role expects, usually `execute`).
- **Dependency Injection**: Roles load their strategies dynamically based on the schema.

## 6. Future Agentic Calls

*   **Context**: When working on this repo, always check `turtle_schema.json` to understand the current active configuration.
*   **Verification**: After creating a new strategy or role, you can "test" it by updating `turtle_schema.json` to point to the new code.

## 7. Maintenance

*   **Installer Updates**: The `install.lua` file contains a hardcoded archive of the project files. **Whenever you modify any file in the `turtleos/` directory or `boot.lua`, you MUST update the corresponding entry in `install.lua`.** This ensures that users running the installer get the latest version of the code.

