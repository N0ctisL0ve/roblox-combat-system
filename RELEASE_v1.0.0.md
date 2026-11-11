# v1.0.0

First release. Three hit M1 combo, block, hitstun, i-frames, and every hit check on the server.

## Files

- `replicated_storage.rbxmx` - config, types, math, remotes, goes into `ReplicatedStorage.Combat`
- `server_script_service.rbxmx` - combat service, validator, state, debug parts, goes into `ServerScriptService`
- `starter_player_scripts.rbxmx` - input, prediction, effects, goes into `StarterPlayerScripts`
- Source code zip is the same scripts plus README and the packaging script

## Install

Insert the three files with `Insert from File` into ReplicatedStorage, ServerScriptService and
StarterPlayerScripts, then press Play. The remotes are created automatically.

## What it does

- Client sends `AttackRequest` and `SetBlocking`, nothing else. Positions, targets, damage and
  the combo index are all derived on the server.
- Hitboxes are `GetPartBoundsInBox` / `GetPartBoundsInRadius` with the attacker filtered out.
- Reach, angle and line of sight are checked per target. Ping adds a small capped allowance.
- Spam is limited by a minimum interval and a one second sliding window, excess requests are
  dropped without a reply.
- `DEBUG_HITBOXES = 1` in `Shared/CombatConfig.luau` draws the query volume: green on a hit,
  red on a miss or a rejected target.
- Client predicts the animation, sound and swing arc, buffers clicks at the end of a swing,
  and both sides get hitstop plus camera shake.
- Knockback is a short `LinearVelocity` burst with hitstun. WalkSpeed is never modified.

## Not in this build

- No rewind, so fast moving targets at high ping can sit slightly outside the box.
- No speed hack or teleport detection.
- Animations and sounds are empty by default, the system runs without them.
