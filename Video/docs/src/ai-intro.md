# Larry Seyer Video Effects: reference for AI agents

Version {{VERSION}}. This file is generated from the effect files by `tools/build_docs.lua`; edit those, not this.

Larry Seyer Video Effects adds {{COUNT}} video effects to REAPER. Every effect is a REAPER **Video Processor** preset named
`LS <Category>: <Title>` (for example `LS Color: Color Grade`). They work in any REAPER project and render
like any other Video Processor; the Larry Seyer Video Effects panel is optional.

## 1. Before you start

- **Presets must be installed** in the REAPER you are driving. They are installed the first time the user runs
  *Larry Seyer Video Effects* or *Larry Seyer Video Effects - Install or update presets* from the Actions list, or when a script calls
  `LS.ensure_presets()` (below).
- **Find the pack folder** with `reaper.GetExtState("LS_VIDEO_FX", "path")` (set whenever either script runs;
  the path ends with a slash). If it is empty, ask the user to run the panel once from the Actions list.
  A ReaPack install lives in `<resource path>/Scripts/Larry Seyer/Video/`.
- `LS.ensure_presets()` is cheap; call it at the start of every script.
- **Project video size** (Project Settings > Video) is the user's setting; scripts do not need to set it. It decides the output frame. Every position and size in these
  effects is a fraction of the frame, so the same settings work at 1920x1080, 3840x2160 or 1080x1920.

## 2. Recommended: the scripting API (ReaScript Lua)

```lua
local LS = dofile(reaper.GetExtState("LS_VIDEO_FX", "path") .. "lib/agent.lua")
LS.ensure_presets()

-- tracks and media
local titles = LS.add_track("Titles", 0)                        -- inserted at index 0 = top = in front
local screen = LS.add_track("Screen", 1)
local item = LS.add_media(screen, "/path/clip.mp4", 0, 6)       -- track, file, position[, length[, offset]]; no fades
                                                                -- (default length: the file's, 5 s for still images)
local item2 = LS.add_media(screen, "/path/next.mp4", 5, 6)      -- overlaps the first item by 1 s
LS.crossfade(item, item2)                                       -- linear fades across the overlap (needed by transitions)

-- effect on one clip
local fx = LS.add_to_item(item, "LS Color: Color Grade", { temp = 0.25, sat = 1.1 })
-- effect on a whole track (also how transitions and split screens are used)
local tfx = LS.add_to_track(track, "LS Transition: Dissolve & Dip", { style = 0 })
-- a title, lower third or callout: creates a transparent title item; the text is the item name.
-- Arguments: track, position, length, text, effect, controls[, fade_in = 0.5, fade_out = 0.5]. Returns item, fx.
local titem, lfx = LS.add_title(titles, 2.0, 5.0, "Jane Doe | Drums", "LS Title: Lower Third", { align = 0 })
-- change controls later
LS.set(item, fx, { contrast = 1.15 })
-- keyframe: control reaches value at project time (seconds); points are linear, the effect's own easing still applies
LS.keyframe(item, fx, "exposure", 10.0, 0.0)
LS.keyframe(item, fx, "exposure", 12.0, 0.6)
-- list controls of an effect
local ctl = LS.controls("LS Transform: Transform")
```

Controls are named by their **variable name** (the `var` column below). Values are real values inside the listed
range, not 0..1 normalized. Choice controls take the option number (0 = first option). On/off controls take 0 or 1.
`LS.*` raises a clear error for unknown effects, unknown controls or out-of-range values.

## 3. Without the API

```lua
local fx = reaper.TrackFX_AddByName(track, "Video processor", false, -1)      -- or TakeFX_AddByName(take, "Video processor", -1)
reaper.TrackFX_SetPreset(track, fx, "LS Color: Color Grade")                   -- always set the preset: a new Video processor
reaper.TrackFX_SetNamedConfigParm(track, fx, "renamed_name", "LS Color: Color Grade")  -- lets the panel recognise it
reaper.TrackFX_SetParam(track, fx, 20, 0.25)                                   -- API index from the tables (temp), real value
```

When driving REAPER through an MCP server or another tool: add the FX named `Video processor`, load the preset by
its exact LS name, then set parameters by **API index** with **real (not normalized) values**. A new Video
processor first loads the user's default preset, so always load the LS preset before setting anything.

## 4. Rules that are not obvious

1. **Item or track.** On an item the effect changes only that clip. On a track it changes everything on that track.
   The *Placement* line of each effect says which is intended. Item effects run first, then track effects, so an
   item's effects travel with that clip through a transition (a blurred area stays on its clip while it slides out).
2. **One item at a time per track.** Where items overlap on a track, REAPER shows only one of them (unless a
   transition effect is on that track). Graphics that overlap in time (a lower third and a callout, two titles) must
   go on **separate tracks**. `LS.add_title` refuses an overlap with an explanation.
3. **Layers.** Video tracks higher in the track list are in front. Effects that place or frame a picture (Transform,
   Picture-in-Picture & Logo, Border & Shadow, Corner Pin, Green Screen Key, Blend Modes, titles, callouts) draw the
   tracks *below* as the background. Put the foreground clip on a track above the background. Nothing on a lower track
   affects a higher one: a credits backdrop or a callout's dimming does not darken a logo on a track above it.
4. **Text.** Titles, lower thirds, credits and callouts take their text from the **item (take) name**. `|` starts a new
   line (`Name | Subtitle`). Credits: one entry per `|`; `Role: Name` makes two columns. Put these effects on a
   transparent title item (`LS.add_title`, or an item whose source is `LS Title Carrier.png` in the pack folder).
5. **Animation from item fades.** Effects with *Animate with = Item fades* animate in over the item's fade-in and out
   over its fade-out (titles, callouts, Picture-in-Picture entrances, Zoom to Region, Spotlight, Magnifier). Set the
   fade lengths (`D_FADEINLEN`, `D_FADEOUTLEN`, linear shape) to set the timing. A zero fade means no animation at
   that end (fade-out 0 keeps it fully shown to the end). Item fades never fade the picture by themselves; they only
   drive these animations and transitions. Scrolling Credits ignores fades.
   When an item's fades already serve a crossfade, set *Animate with* to Manual (`animsrc = 1`) **and** keyframe
   `amount` (0 = off, 1 = full). Keyframe a straight 0 to 1 ramp: the effect applies its own easing to it. Once
   `amount` has keyframes, its static value no longer matters.
6. **Transitions.** Put a Transition effect on the **track**, then make two items on that track overlap **and
   crossfade**: fade-out on the first item and fade-in on the second, both as long as the overlap (`LS.crossfade`
   does this). Without the fades there is a hard cut. Every crossfade on the track becomes the transition; one
   instance serves them all.
   Manual mode instead blends this track into the track below with a keyframed `progress` from 0 to 1.
7. **Keyframes** are REAPER FX envelopes holding real values, with linear points. Take-FX envelopes use time relative
   to the item start (`LS.keyframe` converts project time for you). An effect's own easing still shapes the motion.
8. **Durations.** Ken Burns `dur` and Scrolling Credits `dur` are in seconds: set them to the item length.
9. **Order.** Effects on one item or track run top to bottom: put color correction before titles or borders.
10. **How much.** Subtle color changes: temperature 0.1-0.2, saturation 1.05-1.15, contrast 1.05-1.15. Clearly
    visible: temperature 0.3-0.5, saturation 1.3. Examples in section 6 show typical values for each effect.
11. **Speed.** At 4K most effects are cheap; Color Grade with hue rotate or vibrance, Hue Curves, Isolate Color, Looks,
   Sharpen, Green Screen, Blend Modes, Luma dissolve and Shape Wipe work per pixel and render more slowly.
12. **Check your work** by rendering a short section or asking the user to look at the Video window. Turn off
    preview-only switches before rendering: Color Grade `split`, Isolate Color `showmask`, Zoom to Region `showbox`,
    Green Screen `showmatte`. That is the complete list, and all four are off by default.

## 5. Recipes for tutorial videos (Larry Seyer Drums, Sparks of Light)

```lua
local LS = dofile(reaper.GetExtState("LS_VIDEO_FX", "path") .. "lib/agent.lua")
LS.ensure_presets()
local titles  = LS.add_track("Titles", 0)     -- titles and lower thirds, in front
local callouts = LS.add_track("Callouts", 1)  -- a second graphics track, for graphics that overlap the titles
local screen  = LS.add_track("Screen", 2)     -- the screen recording / screenshots

-- Opening title over the first 5 seconds
LS.add_title(titles, 0, 5, "Energy Levels | Larry Seyer Drums", "LS Title: Title & Subtitle", { anim = 1, backdrop = 1 })

-- Presenter lower third
LS.add_title(titles, 6, 6, "Larry Seyer | Creator, Larry Seyer Drums", "LS Title: Lower Third", { style = 0, align = 0 })

-- Callout pointing at a control: box over the control, label beside it (fractions of the frame)
LS.add_title(callouts, 10, 6, "Swing", "LS Tutorial: Callout",
  { bx = 0.16, by = 0.76, bw = 0.06, bh = 0.035, lx = 0.38, ly = 0.78, anim = 2 })

-- Zoom into part of a screen recording for one item (split the item first so it covers the zoom;
-- if that item's fades are part of a crossfade, use animsrc = 1 and keyframe amount instead)
LS.add_to_item(zoom_item, "LS Transform: Zoom to Region", { rx = 0.05, ry = 0.1, rw = 0.3, rh = 0.2 })
reaper.SetMediaItemInfo_Value(zoom_item, "D_FADEINLEN", 0.6)   -- zoom-in time
reaper.SetMediaItemInfo_Value(zoom_item, "D_FADEOUTLEN", 0.6)  -- zoom-out time

-- Dissolve between consecutive screenshots on the screen track: overlap them by 0.5 s and crossfade
local shot1 = LS.add_media(screen, "/path/shot1.png", 20, 6)
local shot2 = LS.add_media(screen, "/path/shot2.png", 25.5, 6)
LS.crossfade(shot1, shot2)
LS.add_to_track(screen, "LS Transition: Dissolve & Dip", { style = 0 })

-- Logo in the corner for the whole video: logo PNG item on a track above everything
LS.add_to_item(logo_item, "LS Transform: Picture-in-Picture & Logo", { corner = 8, size = 0.12, shape = 0, border = 0, anim = 1 })

-- Hide private information
LS.add_to_item(item, "LS Tutorial: Blur or Pixelate Region", { rx = 0.62, ry = 0.04, rw = 0.3, rh = 0.05 })

-- End credits over the last 12 seconds
LS.add_title(titles, end_time - 12, 12, "Larry Seyer Drums | Created by: Larry Seyer | Thanks for watching",
  "LS Title: Scrolling Credits", { dur = 12 })
```

## 6. Effect reference
