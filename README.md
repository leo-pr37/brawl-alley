# Brawl Alley - Streets of Fury

A 3D beat-em-up arcade game for Roblox, inspired by TMNT and Streets of Rage. Fight waves of enemies in a gritty street alley — solo or co-op!

## Features

- **3D Beat-em-up Combat** — Light attacks, heavy attacks, combos, blocking, and dodging
- **R15 Character Rig** — Player and enemy fighters use R15 rigs for less boxy silhouettes and smoother joint motion
- **3 Enemy Types** — Thugs (basic), Brawlers (tanky), Speedsters (fast)
- **Level Selector + Difficulty** — Choose Alley District, Subway Yard, or Rooftop Run with Easy/Normal/Hard before starting
- **Wave System** — 8 handcrafted opening waves per level + endless procedural generation
- **Co-op Multiplayer** — Fight together with friends
- **Full HUD** — Health bar, score, combo counter, wave indicator
- **Game Loop** — Start screen → gameplay → game over → restart
- **Procedural Arena** — Street/alley environment built entirely with code

## Controls

| Input | Action |
|-------|--------|
| WASD | Move |
| Left Click | Light Attack |
| Hold Left Click | Heavy Attack |
| Right Click | Block |
| Shift / Q | Dodge |
| Mouse | Aim direction |

## Combat System

- **Light Attack**: Quick punch, chainable into combos (up to 4 hits)
- **Heavy Attack**: Hold click to charge, deals 2.5x damage with knockback
- **Block**: Reduces incoming damage by 75%, shown as a shield visual
- **Dodge**: Quick dash with invincibility frames, 1s cooldown
- **Combos**: Chain light attacks for increasing damage multipliers (1.0x → 1.5x)

## Setup & Installation

### Prerequisites
- [Roblox Studio](https://www.roblox.com/create)
- [Rojo](https://rojo.space/) (v7+)

### Installing Rojo

**Option A: Aftman (recommended)**
```bash
cargo install aftman
aftman init
aftman add rojo-rbx/rojo
```

**Option B: Direct download**
Download from [Rojo releases](https://github.com/rojo-rbx/rojo/releases) and add to PATH.

**Option C: Foreman**
```bash
foreman install
```

### Also install the Rojo Studio Plugin
1. In Roblox Studio: Plugins → Manage Plugins → Search "Rojo" → Install
2. Or run `rojo plugin install` from this project directory

### Syncing to Roblox Studio

1. Clone this repo:
   ```bash
   git clone https://github.com/leo-pr37/brawl-alley.git
   cd brawl-alley
   ```

2. Start the Rojo dev server:
   ```bash
   rojo serve
   ```

3. Open Roblox Studio and create a new Baseplate place

4. In Studio, click the Rojo plugin → Connect (default: localhost:34872)

5. The project will sync automatically. You should see:
   - `ServerScriptService/Server/` — server scripts
   - `StarterPlayerScripts/Client/` — client scripts
   - `ReplicatedStorage/Shared/` — shared modules
   - Arena built in Workspace
   - Custom lighting

### Play Testing

1. With Rojo connected, press **Play** (F5) in Studio
2. On the start screen, select a level and difficulty, then press **START BRAWL**
3. For co-op testing, use **Test → Start** with 2+ players

## Project Structure

```
brawl-alley/
├── default.project.json     # Rojo project configuration
├── README.md
└── src/
    ├── server/
    │   └── GameManager.server.lua    # Wave management, enemy AI, damage, arena
    ├── client/
    │   ├── CombatController.client.lua  # Input handling, attacks, blocking
    │   ├── CameraController.client.lua  # Arcade-style camera
    │   └── UIController.client.lua      # HUD, menus, effects
    └── shared/
        ├── CombatConfig.lua    # Combat tuning values
        ├── EnemyTypes.lua      # Enemy definitions and wave data
        └── Utils.lua           # Shared utilities (NPC creation, health bars)
```

## Enemy Types

| Type | Health | Speed | Damage | Behavior |
|------|--------|-------|--------|----------|
| Thug | 40 | 12 | 8 | Basic melee, approaches and punches |
| Brawler | 70 | 10 | 12 | Tanky, high knockback resistance |
| Speedster | 25 | 22 | 6 | Fast, attacks quickly, flanks |

## Architecture

- **Server** handles all authoritative game logic: damage, spawning, wave progression, AI
- **Client** handles input, camera, UI rendering, and visual effects
- **Shared** modules provide configuration and utilities used by both
- Communication via RemoteEvents for all client-server interaction
- Enemy AI runs on server at 5 ticks/second for performance
- Blocking/dodging state synced to server for damage reduction

## License

MIT
