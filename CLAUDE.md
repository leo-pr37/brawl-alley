# Brawl Alley

3D beat-em-up arcade game for Roblox. Wave-based combat, co-op multiplayer, 5 levels.

## Tech Stack
- Luau (Roblox's typed Lua)
- Rojo v7+ for filesystem-to-Roblox syncing
- No external dependencies beyond Roblox engine services

## Project Structure
```
default.project.json       — Rojo config (maps src/ to Roblox services)
src/
  server/
    GameManager.server.lua — Core game loop, wave spawning, AI, damage (authority)
    ArenaBuilder.lua       — Procedural level generation (5 levels)
  client/
    CombatController.client.lua — Input, attacks, combos, items, stamina
    UIController.client.lua     — HUD, menus, music, shop, visual effects
    CameraController.client.lua — Third-person over-shoulder camera
    DevPanel.client.lua         — Debug panel (F9/backtick)
  shared/
    CombatConfig.lua       — All tuning values (damage, cooldowns, prices, audio IDs)
    EnemyTypes.lua         — 3 enemy types, 5 levels, 8 handcrafted waves + procedural
    CharacterStates.lua    — State definitions (Idle, Walking, Attacking, Dead, etc.)
    CharacterBuilder.lua   — Builds R15 humanoid rigs from code (no asset deps)
    AnimationManager.lua   — Procedural animation via Motor6D tweening (no animation assets)
    RuntimeStateMachine.lua — Lightweight state machine with locks & transitions
    Utils.lua              — NPC creation, health bars, distance calcs
    ComicBubbles.lua       — Comic-style hit effects ("POW!", "BAM!")
assets/
  npcs/                    — NPC model files (Roblox binary)
```

## How to Run
1. Install Rojo v7+ and the Rojo Studio plugin
2. `rojo serve` from project root
3. Open Roblox Studio → new Baseplate → Rojo plugin → Connect
4. F5 for solo play, Start for multiplayer testing

## Architecture
- **Server-authoritative**: all damage, spawning, wave progression, AI on server
- **Client-side prediction**: attacks render immediately, server validates
- **~20 RemoteEvents** for client-server communication
- **Procedural everything**: rigs built from code, animations via Motor6D, levels generated

## Combat System
- Light attack (8 dmg), Heavy (20, charged), Grab/Suplex (24)
- 4-hit combos with escalating multipliers (1.0x → 1.5x)
- Block (75% reduction), Dodge (0.4s i-frames, 20 stud dash)
- Stamina system (max 100, drains on attacks/sprint, regens 14/s)

## Levels
Alley District, Subway Yard, Rooftop Run, Warehouse, Fight Club

## Enemies
Thugs (tanky), Brawlers (heavy hitters), Speedsters (fast/evasive)

## Conventions
- Centralize tuning in CombatConfig.lua
- Use `game:GetService()` and `task.*` API
- ModuleScript pattern with table returns
- Luau type hints where helpful
