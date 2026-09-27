# Project Rain OSS — single-file build

This repo ships the script as a module tree (`src/`) + assets (`assets/`). The
upstream loader that glued everything together was stripped for the OSS release
("Omitted. Do this yourself. <3"), so this tree adds a community build system:

```
python3 tools/build.py        # -> project-rain.lua (single file, ready to execute)
```

Dependency: `pip install zstandard` (the runtime inlines assets as
`base64(zstd(bytes))`, matching `decode_asset()` in `init.lua`).

The output `project-rain.lua` is one chunk: a small runtime implements
`require("@src/...")` (cached), `list_modules("glob/*")` and
`inline_asset_b96("@assets/...")`, registers all 273 modules + 16 assets, then
runs `src/globals.lua` followed by the original entrypoint `src/init.lua`.
Module sources compile lazily via `loadstring` on first `require`, chunk names
are set to their `@src/...` path so tracebacks stay readable.

## Runtime hardening (loads anywhere, not only in Deepwoken)

The upstream init chain hard-waits / hard-kicks on Deepwoken-only objects. The
build now loads the full UI in any place and only engages Deepwoken-specific
logic when the game actually provides those objects:

| spot | before | now |
| --- | --- | --- |
| `features/hooking.lua` | `WaitForChild("Requests")` hung init forever outside Deepwoken; kicked when ban remotes missing | place whitelist: remote hooks + anti-ban kicks only run in Deepwoken places; `ClientActor` wait is time-boxed |
| `STR_TBL_SF_INVOKE` | stripped global -> `hooking.lua:17 attempt to call a nil value` kick | passthrough in `globals.lua` (identity, like other obf macros) |
| `base_require` | stripped global used to require Deepwoken `ModuleScript`s (`CollisionUtils`, `EffectReplicator`, `KeyBinds`, camera Popper, ...) | provided by the bundle runtime as the pristine `require` for instances |
| `utility/custom_font.lua` | wrong-case asset path + unbounded font prewarm could hang init | both case paths tried, everything pcall'd, 5s cap, Gotham fallback |
| `utility/deepwoken/general_utilitys.lua` | `WaitForChild("Modules")` **and** `WaitForChild("KeyBinds")` hung init outside Deepwoken | bounded lookups, inert placeholders otherwise (`IsActionHeld -> false`, stubbed collision utils) |
| `features/auto-builder/auto_builder.lua` | line 2 hard-required `ReplicatedStorage.Info.DataReplication` -> hard error killed init at `init:298` outside Deepwoken | guarded require; inert builder stub (every method answers with a notice + `false`) |
| `utility/deepwoken/effect_replicator_handler.lua` | background `WaitForChild("Requests")` chain spammed infinite-yield warnings outside Deepwoken | instant `FindFirstChild` first, bounded waits after; silently skips when absent |
| `features/visuals/base_esp.lua` | 9 unbounded `WaitForChild` folders (`Thrown`, `Live`, `NPCs`, `Shops`, ...) + `MarkerWorkspace` chain hung init after the UI showed | all resolved once in parallel bounded workers; watcher blocks no-op when the folder is absent |
| `features/visuals/player_esp.lua` | unbounded `WaitForChild("Live")` hung init | 15s bounded lookup, watcher skipped when absent |
| `init.lua` | no way to know "are we in deepwoken" early; automation autostart hard-waited on `Requests` | `aztup.is_deepwoken` (place-id whitelist OR signature folders) drives instant skips everywhere; autostart gated + bounded |
| `features/auto-parry/defend-action-manager.lua` | module-level Heartbeat loop crashed every frame outside Deepwoken (`EffectReplicator` global is nil there - 30 errors/sec) | loop only armed when `aztup.is_deepwoken`; KeyBinds lookup instant outside |
| `features/{combat,buttons,removals,auto-parry}/...` (7 modules) | `WaitForChild` fallbacks burned the full loader timeout (8s each) outside Deepwoken | all deepwoken-only lookups are `FindFirstChild`-instant unless `aztup.is_deepwoken` |
| `features/loader.lua` (reimplemented) | a single feature hard-waiting at load would freeze startup | every feature require runs in a worker thread, cancelled after 8s (20s for entry points) with a warn instead of a hang |
| `automation/loader.lua` | farm modules loading serialized; any hard-wait froze startup | parallel workers, one 12s global budget, late/skipped farms reported |
| bundle runtime | plain sequential `require` | in-flight dedup so parallel workers never double-load a module (cycle-tolerant) |

## What was stripped upstream & how it was reimplemented here

| stripped file | replacement |
| --- | --- |
| `src/features/loader.lua` | full reimplementation: global `Feature` class + loads all 130 self-registering feature modules with per-module `xpcall` |
| `src/luarmor_init_script.lua` | no-op stub (no Luarmor/key system in OSS) |
| `src/security/user_service.lua` | offline user service (everything ungated, nobody is staff) |
| `src/main_menu/loader.lua` | notify-only stub |
| `src/utility/setup_auto_load.lua` | no-op stub (Luarmor-only upstream) |
| `src/features/auto-parry/builder.lua` | **working reimplementation**: draggable Timing Builder GUI — loads tracks clicked in the "Timing Logger", timeline with per-action markers, action add/cycle/nudge/delete, saves `rw_timings/<name>.json` in exactly the animator-handler's format and hot-reloads via `getgenv().load_timings()` |
| `src/features/auto-parry/data/custom_timings.lua` | working reimplementation: reads `.json`/`.lua` timing files from `rw_timings` / `Project Rain/Timings`, `:sync()` iterator + `:lookup(id)` |
| `src/features/buttons/refresh.lua` | working reimplementation (respawn in place, per the button's own tooltip) |
| `src/features/misc/spotify_widget.lua` | **working reimplementation**: real draggable now-playing frame (position persisted via SaveManager like upstream), visibility toggle + bridge url box in the Config tab; talks to any localhost helper exposing `GET /now-playing` and `POST /play-pause\|/next\|/previous` |
| `src/features/misc/mod_detector/group_members.lua` | empty `{userId -> role}` map — fill in yourself |
| `src/features/removals/mantra_revealer/mantras.lua` | empty `{card name -> mantra}` map — fill in yourself |
| `src/utility/deepwoken/deepwoken_meshes.lua` | empty `{mesh id -> item name}` map — fill in yourself |
| `assets/brayden.png` | 1x1 placeholder PNG |
| `src/ui/tabs/ui.lua` | upstream file, additive patch: "Spotify" section (toggle + bridge url) driving the reimplemented widget |

### Timing builder usage

1. Combat tab -> enable **Timing Logger** (set its range slider).
2. Let a mob/player attack you; entries appear in the logger. Click one to load it into the builder (opens automatically) or open manually with **Show Timing Builder**.
3. Click on the timeline to drop a Parry at that second, or use `+ Parry / + Dodge / + Forced Full Dodge / + Start Block`. Rows: cycle type, nudge `-`/`+` (10 ms) / `++` (100 ms), `x` delete. `++` and `-`/`+` steps are 100 ms and 10 ms.
4. Optionally pick an **action group** (M1/Critical/Spell/Bell/Untagged).
5. **save** -> writes `rw_timings/<name>.json` and calls the auto-parry's hot reload. **delete** removes the file again.

Saved JSON shape (consumed verbatim by the handler):

```json
{ "name": "mino jab", "ids": ["123456789"], "action_type": "M1",
  "actions": [ {"type": "Parry", "when": 0.45} ] }
```

All replacements are marked with a `[project rain oss]` header comment.

Per the repo's `CLAUDE.md`: keep the credits/branding intact if you fork or
redistribute this.
