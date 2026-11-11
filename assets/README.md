# assets

Images for the README. Nothing captured yet, the README points at the first one.

| file | what it should show |
|---|---|
| `hitbox_debug.gif` | 3-5 seconds of combo on a dummy with `DEBUG_HITBOXES = 1`, green box on every hit. Side camera, `Scriptable`, 30-60 fps. |
| `hitbox_miss.png` | A swing that misses: red hitbox, red markers on the targets that got rejected by angle or reach. |
| `wallbang_blocked.png` | Player and target behind a wall. The box covers the target but the marker is red because the ray hit the wall. |

## How I take them

1. `Shared/CombatConfig.luau` -> `DEBUG_HITBOXES = 1`.
2. For stills I bump `Debug.Lifetime` to 2-3 seconds, the GIF keeps 0.35.
3. Play, walk up to the target, swing M1.
4. Side camera, from the client command bar:

```lua
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(Vector3.new(10, 8, 10), Vector3.new(0, 3, 0))
```

5. Stills with PrtScn or Game Bar, GIF with OBS or Game Bar.

Put `DEBUG_HITBOXES` back to 0 and `Lifetime` to 0.35 before pushing anything.
