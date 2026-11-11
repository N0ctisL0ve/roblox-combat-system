# Combat system

Server side melee combat for Roblox. Three hit M1 combo, block, hitstun, short i-frames,
and every swing is validated on the server. The client sends two things: "I pressed attack"
and "I hold block". No positions, no targets, no damage.

![hitbox debug](assets/hitbox_debug.gif)

Numbers from a test on a 500 hp dummy: 9 + 11 + 16 damage for a full combo, WalkSpeed stays
at 16 the whole time, including stun, block and mid swing.

## Layout

```
Shared/   -> ReplicatedStorage.Combat    config, types, math, remote helpers
Server/   -> ServerScriptService         attack flow, hit validation, state, debug parts
Client/   -> StarterPlayerScripts        input, prediction, buffering, effects
tools/    build_package.py packs the .luau files into .rbxmx for Studio
```

- `Shared/CombatConfig.luau` - damage, cooldowns, hitbox sizes, tolerances. Everything I tune lives here.
- `Shared/CombatTypes.luau` - types, no runtime code.
- `Shared/CombatMath.luau` - flatten, horizontal dot, cone check, ping allowance.
- `Shared/Remotes.luau` - creates the five remotes on the server, waits for them on the client.
- `Server/Combat/CombatService.luau` - request handler, combo index, damage, knockback.
- `Server/Combat/HitboxValidator.luau` - the actual checks.
- `Server/Combat/StateService.luau` - per player state and its lifetime.
- `Server/Combat/HitboxDebug.luau` - draws the query volume.
- `Client/Combat/CombatController.luau` - input, prediction, buffer, hitstop.
- `Client/Combat/EffectsController.luau` - sounds, swing arc, camera shake.

## How a swing goes

Client presses M1 and fires `AttackRequest` with no arguments. After that it is all server:

1. `CombatService` checks the request rate, then the state (stunned, blocking, already swinging).
2. Takes the next index in the combo chain. The index is server side, the client never sends it.
3. `HitboxValidator.Validate` builds the box from `HumanoidRootPart` and the attack offset.
4. `GetPartBoundsInBox` finds candidates, or `GetPartBoundsInRadius` for the heavy.
5. Each candidate gets a distance check, an angle check and two rays (body, then head).
6. Survivors take damage, hitstun, i-frames and knockback.

`AttackConfirmed` goes to players near the swing, `HitFeedback` to the attacker and the target.

## Validation

Distance and angle come from the hitbox, not from anything the client claims:

- reach: `hitbox forwardExtent + BaseReachTolerance + TargetPadding + ping allowance`
- angle: horizontal dot against `MaxAngleDegrees`
- walls: ray to the target root, then to the head

The first two swings reach about 11 studs once the tolerances are added, the heavy a bit more.
A 30 stud reach exploit finds nothing at all, because the query is bounded by the box and the
box is built on the server.

## Ping

There is no rewind. Keeping a position history for every player is a lot of bookkeeping for
a small gain, so lag is covered with a tolerance instead:

```lua
local ping = math.clamp(player:GetNetworkPing() * PingSafetyMultiplier, 0, 0.5)
local reachBonus = math.min(ping * PingReachBudget, MaxPingCompensation)
local angleBonus = math.min(ping * PingAngleDegreesPerSecond, PingAngleBudgetDegrees)
```

`GetNetworkPing` returns one way latency, so the multiplier is 2 to get RTT. At 120 ms that
is about 4 studs and 8 degrees: enough to hide normal lag, nowhere near a cross map aura.

## Walls

Two rays, root then head. The attacker is excluded from the filter and the target's own parts
do not count as blockers. When the root ray catches a low ledge the head ray usually still
passes, which matches what the player saw on screen.

## Spam

Two limits sit in front of the spatial query: `MinRequestInterval` (0.09 s) and a one second
sliding window of `MaxRequestsPerSecond` (8). Over the limit the request is dropped without a
reply, so an exploiter gets nothing to flood the channel with.

## State

`StateService` keeps a plain table keyed by player: attacking, stunned, blocking, i-frames,
plus the timestamp each one ends at. A Heartbeat tick at 30 Hz clears expired flags and copies
them to Player attributes.

The attributes are a mirror, not the source. The client uses them to gate input and pick
animations, and attribute writes from a client never replicate, so setting `Stunned = false`
locally does nothing.

`IsAttacking` lasts exactly the attack cooldown. `Stunned` comes from `attack.Hitstun`.
`Blocking` cuts damage to `BlockDamageMultiplier` and skips stun and knockback, but only
inside `BlockConeDegrees`. i-frames are 0.18 s and exist so a single swing cannot tick twice.

WalkSpeed is never touched. Stun and block take away actions, not movement.

## Client side

Input: M1, touch or ButtonR2 to attack, RMB or F to block.

Prediction: on press the client plays the animation, the swing sound and the arc right away,
then fires the remote. If the server rejects, `AttackRejected` stops the track and rolls the
combo index back one.

Buffering: a click inside the last `InputBufferWindow` (0.18 s) of a swing is kept and started
on the first frame the cooldown is over. The buffer also lives 0.35 s past the attack end,
because the server clears `IsAttacking` on a tick and that lands after the client's own
cooldown. Without the grace the buffered click expires right when the server would accept it.
Earlier clicks are ignored, otherwise mashing turns into a queue.

Hitstop: `HitFeedback` reaches both sides. Both clients drop their tracks to 0.1 speed for
`HitstopDuration` and restore them on a timer. Camera shake is bound in `BindToRenderStep`
above the camera priority, and getting hit shakes harder than landing a hit.

Knockback: server side `LinearVelocity` on the target root, `RelativeTo = World`, removed
after `KnockbackDuration`. BodyVelocity is deprecated.

## Debug hitboxes

Set `DEBUG_HITBOXES = 1` in `Shared/CombatConfig.luau` and the server draws every query.
Green box if something got hit, red if not, plus a marker on each target: green when damage
went through, red when distance, angle or a ray rejected it. Parts go into `Workspace.CombatDebug`
and Debris removes them after `Debug.Lifetime`.

Back to 0 for release. The flag check is the first line of the debug module, so nothing gets
built at all.

## Animations and sounds

Every id in the config is empty on purpose, the system runs without assets. To add them, drop
`Animation` objects into `ReplicatedStorage.Combat.Animations` named `M1_Left`, `M1_Right` and
`M1_Heavy`. The client looks there first and falls back to `AnimationId` from the config, so
uploaded animations do not need a code change. Sounds are plain `rbxassetid://` values in
`Effects.*` and `attack.SwingSoundId`.

## Install

Take the three `.rbxmx` files from [Releases](../../releases) and use `Insert from File`:

| file | into |
|---|---|
| `replicated_storage.rbxmx` | ReplicatedStorage |
| `server_script_service.rbxmx` | ServerScriptService |
| `starter_player_scripts.rbxmx` | StarterPlayerScripts |

Then press Play, the remotes show up under `ReplicatedStorage.CombatRemotes`. With Rojo it is
just `rojo serve`, `default.project.json` already maps every service.

## Known issues

- No rewind, so a target moving fast at high ping can be slightly outside the box. The ping
  allowance is the patch, not a fix.
- `EffectsController` makes a new Part for every sound and burst. Fine for a few players,
  needs a pool on a full server.
- Other players see a swing when `AttackConfirmed` arrives, so their view lags by RTT. I play
  the animation locally for the attacker only, double playing it looked worse.
- The animations I tested with were registered inside Studio and only live for that session.
  Real uploads are still pending.
- Speed hacks and teleports are out of scope, that is movement anti cheat territory.

Private repo, built for my own project. Media in `assets/` is not captured yet, the shot list
is in `assets/README.md`.
