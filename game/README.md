# Hadudu AI vs AI (Godot 4.4.1)

A 2D AI-vs-AI starter project inspired by the Bangladeshi national game "Hadudu", built for **Godot 4.4.1** (Vulkan). No external art required — players are procedural circles.

## Run
1. Open **Godot 4.4.1**.
2. `Import` this folder (or open `project.godot`).
3. Press **Play** (or open `res://game/Game.tscn` and run). Click **Start Round**.

## Controls / Flow
- **Start Round**: spawns two teams (5v5) with randomized `energy` and `speed`.
- The round runs for a fixed number of turns (configurable in `Game.gd`).
- Players move via a minimax AI with alpha-beta pruning.
- HUD shows round status and each player's Energy/Speed bars.

## Files
- `res://game/util.gd` – `create_circle_texture()` using Godot 4 `Image.create(width,height,...)` + `ImageTexture.create_from_image()` (no lock/unlock).
- `res://game/Player.tscn` – Minimal Player scene (Node2D + Sprite2D).
- `res://game/Player.gd` – Player logic (robustly creates/uses Sprite2D).
- `res://game/AI.gd` – Static alpha-beta minimax for small discrete moves.
- `res://game/Fuzzy.gd` – Optional aggression helper.
- `res://game/Game.tscn` – Main scene.
- `res://game/Game.gd` – Round control, spawning, HUD creation & updates.
- `res://game/README.md` – This file.

## Config knobs (edit in `Game.gd`)
- `players_per_team` (default 5)
- `round_turns_limit` (default 120)
- `move_distance` (default 8.0)
- Attribute ranges: `energy_min/max`, `speed_min/max`
- `ai_depth` (default 2) — keep small for performance
- `field_rect` — playfield bounds

## Godot 4 Notes (migrated APIs)
- **Image creation**: `var img := Image.create(w,h,false,Image.FORMAT_RGBA8)` (*static*, not instance `.create()`).
- **No `lock()/unlock()` on Image** in G4: we use `set_pixel` directly.
- **No `rect_*`** on Controls: we use `position`, `size`, and `custom_minimum_size`.
- **No `raise()`**: we use `move_to_front()` on `Control`.
- **No `with_alpha()`**: use `Color(r,g,b,a)` and set `.a` explicitly.
- **No `rand_range()`**: use `RandomNumberGenerator` (`randf_range/randi_range`).
- **Ternary**: `a if cond else b` (GDScript 2.0).

## Expected Console Output (sample)
> Note: I cannot execute Godot here, so below is the **expected** log from the provided `print()` statements when you run it locally in Godot 4.4.1.

```
[Game] UI wired: StartButton connected
[Game] Start Round pressed
[Game] Round 1 starting: spawning players...
[Game] Spawned Team 0 Player 0 at (120, 88) E=83.2 S=140.1
[Game] Spawned Team 1 Player 0 at (708, 356) E=72.9 S=128.6
...
[Game] Running turn 1 / 120 — active team=0
[HUD] Updated energies/speeds
[AI] Team 0 chose move for Player 0: (8, 0)
[Game] Running turn 2 / 120 — active team=1
[HUD] Updated energies/speeds
[AI] Team 1 chose move for Player 3: (-5.7, -5.7)
...
[Game] Round finished. Summary: team0_avg_energy=54.2, team1_avg_energy=49.8
```

## Optional mechanics
- A basic possession/ball & scoring hook is stubbed (`TODO` in `Game.gd`) if you want to extend rules.

## License
Public domain / Unlicense. Use at KUET or anywhere else ✌️