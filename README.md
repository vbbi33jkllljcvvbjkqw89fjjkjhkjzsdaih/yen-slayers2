# Yen — Slayers 2 (private)

The Slayers 2 game module: its farms and ESP. Loaded by the loader after the game checker matches Slayers 2 (place list under universe 5595353122).

- `Farm.lua` — the shared farm engine: targeting, the force based mover (BodyPosition, no teleport), the 50 stud platform hops, snap-back halt, attacks and quest helpers.
- `Features/` — one file per feature:
  - `FarmSettings.lua` — weapon, position and the advanced sliders, shared by every farm.
  - `Autofarm.lua`, `BanditFarm.lua`, `BossFarm.lua`, `LevelFarm.lua` — the autofarms.
  - `Esp.lua` — light ESP for players, enemies, NPCs and items.
  - `Loot.lua` — chest and loot collector, tied to the boss it dropped from.
  - `Example.lua`, `Premium/PremiumExample.lua` — templates.

The farms are paused in the shipped build after two "Exploiting" bans on 2026-10-26 (see the main project's docs). ESP is the only Slayers 2 feature shipped right now. Private. Review copy of `Documents\Yen\src`.
