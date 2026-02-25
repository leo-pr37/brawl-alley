# Copilot Instructions for Brawl Alley

This guide helps GitHub Copilot understand the structure and conventions of this Roblox Rojo project.

## Build, Sync, and Run

- **Sync Server:** Run `rojo serve` to start the synchronization server.
- **Studio Connection:** Connect via the Rojo plugin in Roblox Studio (default port 34872).
- **Testing:**
  - **Play Solo (F5):** Starts a local server instance with a player.
  - **Local Server:** Use "Start Server" with 2 players for multiplayer testing.

## High-Level Architecture

The project follows a standard Roblox Client-Server model using Rojo for filesystem syncing:

- **Server (`src/server` → `ServerScriptService/Server`)**
  - Handles game state, enemy AI, wave management, and authoritative damage calculations.
  - Listens to RemoteEvents from clients to validate actions.
  - Updates player data and global game state.

- **Client (`src/client` → `StarterPlayer/StarterPlayerScripts/Client`)**
  - Manages player input (CombatController), camera (CameraController), and UI (UIController).
  - Handles visual effects, local animations, and client-side prediction (e.g., immediate feedback).
  - Communicates with the server via RemoteEvents.

- **Shared (`src/shared` → `ReplicatedStorage/Shared`)**
  - Contains configuration (CombatConfig), utility modules (Utils), and shared logic/constants.
  - Accessible by both server and client.

## Key Conventions

### Roblox Services & API
- **Service Access:** Always use `game:GetService("ServiceName")` at the top of the file.
- **Task Library:** Use `task.wait()`, `task.spawn()`, and `task.delay()` instead of global `wait()`, `spawn()`, and `delay()`.
- **Instance Cleanup:** Use `Debris:AddItem(instance, lifetime)` for temporary visual effects or projectiles.
- **Remote Events:** Define events in `ReplicatedStorage` (often at the root or a dedicated folder). Use `WaitForChild` in client scripts to ensure they exist before access.

### Code Organization
- **Configuration:** Magic numbers and tunable values (damage, cooldowns, speeds) belong in `src/shared/CombatConfig.lua`, not hardcoded in logic scripts.
- **Modules:** Use ModuleScripts for reusable logic. Prefer returning a table of functions.
- **Typing:** Use Luau type checking where beneficial, especially for shared data structures.

### Specific Patterns
- **Input Handling:** Centralize input processing (e.g., in `CombatController`).
- **Animation:** Use `AnimationManager` (shared module) to abstract animation playback logic.
- **State Management:** Keep local state (e.g., `comboCount`, `isBlocking`) in controller scripts, but validate critical actions on the server.
