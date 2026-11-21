# Larry Seyer Video Effects: reference for AI agents

Version 1.1.2. This file is generated from the effect files by `tools/build_docs.lua`; edit those, not this.

Larry Seyer Video Effects adds 43 video effects to REAPER. Every effect is a REAPER **Video Processor** preset named
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
local screen = LS.add_track("Screen")                            -- appended to the track list
local titles = LS.add_track_in_front_of(screen, "Titles")       -- in front of it, whichever Track order is set
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
3. **Layers: in front and behind.** Project Settings > Video > *Track order* decides whether the **top** or the
   **bottom** of the track list is in front; both settings are common. `LS.front_is_top()` tells you which applies
   (true = top track in front). "Behind" means further from the front in that order. Effects that place or frame a
   picture (Transform, Picture-in-Picture & Logo, Border & Shadow, Corner Pin, Green Screen Key, Blend Modes, Split
   Screen, titles, callouts) draw the tracks *behind* them as the background, so put the foreground clip on a track in
   front of the background; `LS.add_track_in_front_of(track, name)` inserts on the correct side. Nothing behind
   affects what is in front: a credits backdrop does not darken a logo on a track in front of it.
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
   Manual mode instead blends this track into the track behind it with a keyframed `progress` from 0 to 1.
7. **Keyframes** are REAPER FX envelopes holding real values, with linear points. Take-FX envelopes use time relative
   to the item start (`LS.keyframe` converts project time for you). An effect's own easing still shapes the motion.
8. **Durations.** Pan & Zoom `dur` and Scrolling Credits `dur` are in seconds: set them to the item length.
9. **Order.** Effects on one item or track run top to bottom: put color correction before titles or borders.
10. **How much.** Subtle color changes: temperature 0.1-0.2, saturation 1.05-1.15, contrast 1.05-1.15. Clearly
    visible: temperature 0.3-0.5, saturation 1.3. Examples in section 6 show typical values for each effect.
11. **Speed.** At 4K most effects are cheap; Color Grade with hue rotate or vibrance, Hue Curves, Isolate Color, Looks,
   Sharpen, Green Screen, Blend Modes, Luma dissolve and Shape Wipe work per pixel and render more slowly.
12. **Check your work** by rendering a short section or asking the user to look at the Video window. Turn off
    preview-only switches before rendering: Color Grade `split`, Isolate Color `showmask`, Zoom to Region `showbox`,
    Green Screen `showmatte`, Multicam Switcher `show` (0 = Program). That is the complete list, and all five are
    off by default.

## 5. Recipes for tutorial videos (Larry Seyer Drums, Sparks of Light)

```lua
local LS = dofile(reaper.GetExtState("LS_VIDEO_FX", "path") .. "lib/agent.lua")
LS.ensure_presets()
local screen   = LS.add_track("Screen")                           -- the screen recording / screenshots
local callouts = LS.add_track_in_front_of(screen, "Callouts")    -- graphics that overlap the titles
local titles   = LS.add_track_in_front_of(callouts, "Titles")    -- titles and lower thirds, in front

-- Opening title over the first 5 seconds
LS.add_title(titles, 0, 5, "Call Outs | Larry Seyer Drums", "LS Title: Title & Subtitle", { anim = 1, backdrop = 1 })

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

-- Logo in the corner for the whole video: logo PNG item on a track in front of everything
LS.add_to_item(logo_item, "LS Transform: Picture-in-Picture & Logo", { corner = 8, size = 0.12, shape = 0, border = 0, anim = 1 })

-- Hide private information
LS.add_to_item(item, "LS Tutorial: Blur or Pixelate Region", { rx = 0.62, ry = 0.04, rw = 0.3, rh = 0.05 })

-- End credits over the last 12 seconds
LS.add_title(titles, end_time - 12, 12, "Larry Seyer Drums | Created by: Larry Seyer | Thanks for watching",
  "LS Title: Scrolling Credits", { dur = 12 })
```

### Multicam: cutting between camera tracks

```lua
-- Camera tracks already on the timeline; the first in the list becomes camera 1.
local mc = LS.multicam_setup({ wide, drums, keys, guitar })      -- returns the new Multicam track (Program view)
local moved = LS.multicam_sync(mc)                                -- line the cameras up by their audio
LS.multicam_cut(mc, 0, 1)                                         -- first shot: camera 1 from the start
LS.multicam_cut(mc, 8.0, 2)                                       -- straight cut to camera 2 at 8 s
LS.multicam_cut(mc, 15.5, 3, "Cross dissolve", 15)                -- 15-frame dissolve to camera 3
LS.multicam_cut(mc, 24.0, 1, "Push", 10, 0)                       -- push to the left, 10 frames
```

Each camera track gets a `LS Transform: Multicam Camera` effect (its `camid` is the camera number; keep it last on
the track). Cuts are square points on the `LS Transform: Multicam Switcher` envelopes `cam`, `trans`, `frames` and
`dir` at the same time. A camera with no video at a moment shows black.

`LS.multicam_sync(mc[, reference_track])` lines the cameras up when they were started at different times: every
clip on every camera track moves to where its audio matches the reference track (default camera 1's track; any
track with audio works, such as a board mix), to within a millisecond, as one undo step. A clip that belongs
before the project start is trimmed at its start instead. It returns one entry per clip:
`{ item, label, pos, shift, note }`; `pos` is nil when the audio did not match (silent, unrelated, or less than
about five seconds in common with the reference) and the clip stays put; `note` explains that, a start trim, or
clock drift over 10 ms. Call it before writing cuts: moving clips after cutting changes what each cut shows.

## 6. Effect reference


| Preset name | Placement | What it does |
|---|---|---|
| `LS Transform: Border & Shadow` | Item or track | Frames a clip with a border (solid, double, glow or gradient), rounded corners, a drop shadow and soft inner shading, over the tracks behind it, a blurred copy or a color. |
| `LS Transform: Camera Shake` | Item or track | Handheld drift, nervous jitter or an earthquake rumble. Automate the amount to hit specific moments. |
| `LS Transform: Corner Pin` | Item or track | Pins the four corners of this clip anywhere on screen, for putting a screen recording onto a monitor or a sign in the shot. |
| `LS Transform: Flip & Mirror` | Item or track | Flips the picture or mirrors one half onto the other, including a four-way kaleidoscope. |
| `LS Transform: Multicam Camera` | Track | Marks a track as a camera for the Multicam Switcher and gives it its number. The Multicam action adds it to each camera track; keep it last in the track's effects (put color matching before it). |
| `LS Transform: Multicam Clicks` | Monitoring FX | Lets you click a camera in the video window to cut to it while the Multicam Switcher shows switcher view. Lives in Monitoring FX (never in renders); the Larry Seyer Video Effects - Multicam action adds it while open and removes it when closed. |
| `LS Transform: Multicam Switcher` | Track | Cuts between cameras like a live switcher. Goes on a Multicam track in front of the camera tracks; its Camera envelope is the cut list and each cut can have its own transition. Switcher view shows the program with every camera underneath and the live one outlined in red. Set it up and cut with the Larry Seyer Video Effects - Multicam action (number keys or clicks in the video window). |
| `LS Transform: Multiview Camera Select` | Item or track | Turns a multiview recording (four cameras in one frame) into a multicam edit: show one camera full screen, two side by side, or one inset over another. Put it on each item and pick the camera, then crossfade items for transitions. |
| `LS Transform: Pan & Zoom` | Item or track | Slow pan and zoom across a photo, screenshot or shot. Set the start and end framing; the move runs for the duration, counted from the item start (item FX) or from the start time (track FX). |
| `LS Transform: Picture-in-Picture & Logo` | Item or track | Places this clip, screenshot or logo in a corner or anywhere on screen, with rounded or circular framing, border, shadow and an entrance animated by the item fade handles. |
| `LS Transform: Reframe & Letterbox` | Item or track | Fits or fills the frame from any source shape, with pan for choosing what stays in view. Use it for vertical short-form video from widescreen footage, blurred-background fills, and cinematic letterbox bars. |
| `LS Transform: Transform` | Item or track | Position, scale, rotate, crop, round corners, border and drop shadow in one pass. Keyframe any control with envelopes. |
| `LS Transform: Zoom to Region` | Item or track | Smoothly zooms into a chosen rectangle, ideal for showing a control in a screen recording. Drag the item fade-in and fade-out to set how long the zoom in and out take, or automate the amount. |
| `LS Color: Color Grade` | Item or track | Primary color grading: lift, gamma, gain and offset wheels, temperature and tint, contrast with pivot, saturation, vibrance, exposure, shadows and highlights, with a before/after split. |
| `LS Color: Curves` | Item or track | Custom curves: a master curve plus red, green and blue curves, each with seven points you drag in the panel. |
| `LS Color: Hue Curves` | Item or track | Hue curves: shift the hue, saturation or brightness of each color range separately, plus saturation by brightness. |
| `LS Color: Isolate Color` | Item or track | Picks one color range and changes it on its own, or keeps it while the rest of the picture goes black and white for a color-pop look. |
| `LS Color: Looks` | Item or track | One-knob film and music-video looks: black and white, sepia, teal and orange, warm film, cool night, bleach bypass, faded vintage, cross process, punch, golden hour, noir and duotone. |
| `LS Color: Vignette` | Item or track | Darkens (or tints) the edges of the frame to pull the eye to the center, with adjustable size, softness, shape and center. |
| `LS Look: Beat Pulse` | Item or track | Punches the picture in time with the music using the project tempo: zoom kicks, light flashes, color split and shake on every beat, half beat or bar. |
| `LS Look: Echo Trails` | Item or track | Moving subjects leave fading echoes behind them, with optional zoom or spin drift for psychedelic tunnels. |
| `LS Look: Film Look` | Item or track | Film grain, gate weave, flicker, dust and scratches, faded blacks, warmth, vignette and optional widescreen bars. |
| `LS Look: Glitch` | Item or track | Digital breakup: torn slices, displaced blocks and color splitting. Automate the amount for hits, or lock bursts to the beat. |
| `LS Look: Glow & Bloom` | Item or track | Bright parts bloom into a soft glow, or the whole image gets a dreamy diffusion like a mist filter. |
| `LS Look: Sharpen & Soften` | Item or track | Crisps up soft or upscaled footage, or softens it for a gentler, diffused look. Positive amounts sharpen, negative amounts soften. |
| `LS Look: VHS & Retro TV` | Item or track | Worn videotape: color bleed, soft picture, scanlines, noise, rolling tracking glitches and an optional PLAY label. |
| `LS Look: Zoom & Motion Blur` | Item or track | Radial zoom blur bursting from a point, or directional blur that streaks the picture at any angle. |
| `LS Transition: Dissolve & Dip` | Track | Put on a track: every crossfade between items on that track becomes this transition, lasting as long as the crossfade. Cross dissolve, dip to black, white or a color, additive, blur and luma dissolves. |
| `LS Transition: Flash, Glitch & Light Leak` | Track | Put on a track: crossfades cut through a white flash, a digital glitch, a warm light leak or a film burn. |
| `LS Transition: Push & Slide` | Track | Put on a track: crossfades become a push, slide, reveal, split or squeeze in any direction, with optional motion blur. |
| `LS Transition: Shape Wipe` | Track | Put on a track: crossfades reveal the next shot through a growing circle, box, diamond, clock sweep, barn doors, angled wipe or blinds, with soft edges and an optional glowing border. |
| `LS Transition: Zoom & Spin` | Track | Put on a track: crossfades punch through with a zoom in, zoom out or spinning zoom, blurred at the peak for speed. |
| `LS Title: Lower Third` | Item (title item) | Name and subtitle bar for the lower part of the screen. Name the item "Name \| Subtitle". Drag the item fade-in and fade-out to set how long it animates on and off. |
| `LS Title: Scrolling Credits` | Item (title item) | Rolling end credits or a sideways news-style crawl. Name the item with lines separated by "\|"; a line like "Drums: Larry Seyer" becomes two columns. Set the duration to the item length. |
| `LS Title: Title & Subtitle` | Item (title item) | Large centered title with an optional subtitle and backdrop. Name the item "Title \| Subtitle". Item fades animate it in and out. |
| `LS Tutorial: Blur or Pixelate Region` | Item or track | Hides part of the picture, such as an email address, serial number or face, with blur, pixelation or a solid box. Stack several to hide several things. |
| `LS Tutorial: Callout` | Item (title item) | Labels a control in a screen recording: an outlined highlight box, an arrow and a label pill, in the style of the Larry Seyer Drums tutorials. The label text is the item name. Item fades animate it in and out. |
| `LS Tutorial: Magnifier` | Item or track | A zoom lens that shows a small detail enlarged somewhere else on screen, with a marker on the original spot and an optional connecting line. Item fades animate it. |
| `LS Tutorial: Spotlight` | Item or track | Dims and optionally blurs everything except one area, with an outline around it, to pull attention to a control or part of the screen. Item fades animate it. |
| `LS Compose: Blend Modes` | Item or track | Blends this layer over the tracks behind it like a photo editor layer: multiply, screen, overlay, soft light, add, subtract, difference, lighten, darken and color dodge. |
| `LS Compose: Green Screen Key` | Item or track | Removes a green or blue backdrop (or any picked color) and puts this clip over the tracks behind it, with spill suppression, edge control and a garbage matte crop. |
| `LS Compose: Split Screen` | Track | Arranges this track and the tracks behind it side by side, stacked, one large with two small, a 2x2 grid or three columns, with gaps, rounded corners and per-panel framing. |
| `LS Time: Freeze & Stutter` | Item or track | Freeze holds the picture from the moment it switches on (automate it for freeze frames). Stutter holds every frame for several frames for a choppy, stop-motion feel. |

### LS Transform: Border & Shadow

*Placement:* an item or a track.

Frames a clip with a border (solid, double, glow or gradient), rounded corners, a drop shadow and soft inner shading, over the tracks behind it, a blurred copy or a color.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `size` | Picture size | 0.85 | 0.1 to 1 | 1 makes picture plus border fill the frame; smaller insets it. |
| 1 | `posx` | Position X | 0 | -1 to 1 | Offset, -1 left to 1 right (half-frame units). |
| 2 | `posy` | Position Y | 0 | -1 to 1 | Offset, -1 up to 1 down. |
| 3 | `radius` | Corner radius | 0.03 | 0 to 0.5 | Corner rounding, fraction of the shorter side. |
| 4 | `bstyle` | Border style | 1 | 0 to 4 | Border look. Options: 0 None, 1 Solid, 2 Double line, 3 Glow, 4 Gradient. |
| 5 | `bwidth` | Border width | 0.008 | 0 to 0.06 | Border width, fraction of frame height (glow spreads three times wider). |
| 6 | `bcr` | Border red | 1 | 0 to 1 | Red part of Border color (0..1). |
| 7 | `bcg` | Border green | 1 | 0 to 1 | Green part of Border color (0..1). |
| 8 | `bcb` | Border blue | 1 | 0 to 1 | Blue part of Border color (0..1). |
| 9 | `b2r` | Second red | 0.24 | 0 to 1 | Red part of Second border color (0..1). |
| 10 | `b2g` | Second green | 0.87 | 0 to 1 | Green part of Second border color (0..1). |
| 11 | `b2b` | Second blue | 0.66 | 0 to 1 | Blue part of Second border color (0..1). |
| 12 | `bopacity` | Border opacity | 1 | 0 to 1 | Border opacity. |
| 13 | `shadow` | Shadow opacity | 0.6 | 0 to 1 | Drop shadow strength. |
| 14 | `shdist` | Shadow distance | 0.015 | 0 to 0.1 | Shadow offset, fraction of frame height. |
| 15 | `shang` | Shadow angle | 120 | -180 to 180 | Direction the shadow falls in degrees (90 = down). |
| 16 | `shsoft` | Shadow softness | 0.03 | 0 to 0.15 | Shadow blur, fraction of frame height. |
| 17 | `scr` | Shadow red | 0 | 0 to 1 | Red part of Shadow color (0..1). |
| 18 | `scg` | Shadow green | 0 | 0 to 1 | Green part of Shadow color (0..1). |
| 19 | `scb` | Shadow blue | 0 | 0 to 1 | Blue part of Shadow color (0..1). |
| 20 | `inner` | Inner shading | 0.25 | 0 to 1 | Darkens the picture toward its edges. |
| 21 | `innersize` | Shading size | 0.06 | 0.005 to 0.3 | How far the inner shading reaches. |
| 22 | `bgmode` | Background | 0 | 0 to 3 | What shows around the framed picture. Options: 0 Tracks behind, 1 Blurred copy, 2 Solid color, 3 Black. |
| 23 | `bgr` | Background red | 0.1 | 0 to 1 | Red part of Background color (0..1). |
| 24 | `bgg` | Background green | 0.1 | 0 to 1 | Green part of Background color (0..1). |
| 25 | `bgb` | Background blue | 0.12 | 0 to 1 | Blue part of Background color (0..1). |

Examples:

- Framed clip over blurred background: `LS.add_to_item(item, "LS Transform: Border & Shadow", { size = 0.85, bstyle = 1, bwidth = 0.008, radius = 0.03, bgmode = 1, shadow = 0.6 })`
- Mint glow frame: `LS.add_to_item(item, "LS Transform: Border & Shadow", { size = 1, bstyle = 3, bwidth = 0.008, bcr = 0.24, bcg = 0.87, bcb = 0.66 })`

### LS Transform: Camera Shake

*Placement:* an item or a track.

Handheld drift, nervous jitter or an earthquake rumble. Automate the amount to hit specific moments.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `amount` | Amount | 0.015 | 0 to 0.1 | Movement in frame widths (0.015 gentle, 0.05 violent). |
| 1 | `rotamt` | Rotation (deg) | 1 | 0 to 10 | Rotation wobble in degrees. |
| 2 | `speed` | Speed | 1.5 | 0.05 to 20 | Wobbles per second. |
| 3 | `style` | Style | 0 | 0 to 2 | Smooth handheld drift, nervous jitter, or a mix (earthquake). Options: 0 Handheld, 1 Jitter, 2 Earthquake. |
| 4 | `seed` | Seed | 1 | 0 to 100 | Changes the random pattern. |
| 5 | `zoomcomp` | Zoom to hide edges | 1 | 0 to 1 | Zooms in slightly so moving edges stay hidden. 0 off, 1 on. |

Examples:

- Handheld feel: `LS.add_to_item(item, "LS Transform: Camera Shake", { amount = 0.01, rotamt = 0.6, speed = 1, style = 0 })`
- Impact hit: `LS.add_to_item(item, "LS Transform: Camera Shake", { style = 2, amount = 0.04 })` Keyframe Amount from 0.04 down to 0 over half a second.

### LS Transform: Corner Pin

*Placement:* an item or a track.

Pins the four corners of this clip anywhere on screen, for putting a screen recording onto a monitor or a sign in the shot.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `tlx` | Top left X | 0.15 | -0.5 to 1.5 | Corner positions are fractions of the frame (0..1, may go off screen). |
| 1 | `tly` | Top left Y | 0.15 | -0.5 to 1.5 | Top left Y. |
| 2 | `trx` | Top right X | 0.85 | -0.5 to 1.5 | Top right X. |
| 3 | `try` | Top right Y | 0.1 | -0.5 to 1.5 | Top right Y. |
| 4 | `brx` | Bottom right X | 0.8 | -0.5 to 1.5 | Bottom right X. |
| 5 | `bry` | Bottom right Y | 0.9 | -0.5 to 1.5 | Bottom right Y. |
| 6 | `blx` | Bottom left X | 0.2 | -0.5 to 1.5 | Bottom left X. |
| 7 | `bly` | Bottom left Y | 0.85 | -0.5 to 1.5 | Bottom left Y. |
| 8 | `opacity` | Opacity | 1 | 0 to 1 | Opacity. |

Examples:

- Screen recording on a monitor in the shot: `LS.add_to_item(item, "LS Transform: Corner Pin", { tlx = 0.31, tly = 0.22, trx = 0.62, try = 0.2, brx = 0.63, bry = 0.55, blx = 0.3, bly = 0.56 })` Put on the screen recording item, on a track in front of the camera shot; move the four corners onto the monitor.

- Drag the four corner points on the panel's frame pad.

### LS Transform: Flip & Mirror

*Placement:* an item or a track.

Flips the picture or mirrors one half onto the other, including a four-way kaleidoscope.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `mode` | Mode | 1 | 0 to 8 | What to flip or mirror. Options: 0 Off, 1 Flip horizontal, 2 Flip vertical, 3 Rotate 180, 4 Mirror left half, 5 Mirror right half, 6 Mirror top half, 7 Mirror bottom half, 8 Kaleidoscope. |
| 1 | `center` | Mirror line | 0 | -0.5 to 0.5 | Moves the mirror line away from the center, -0.5..0.5. |

Examples:

- Kaleidoscope: `LS.add_to_item(item, "LS Transform: Flip & Mirror", { mode = 8 })`

### LS Transform: Multicam Camera

*Placement:* a track.

Marks a track as a camera for the Multicam Switcher and gives it its number. The Multicam action adds it to each camera track; keep it last in the track's effects (put color matching before it).

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `camid` | Camera number | 1 | 1 to 9 | This track's camera number in the Multicam Switcher (1-9). |

Examples:

- Camera 2: `LS.add_to_track(track, "LS Transform: Multicam Camera", { camid = 2 })`

### LS Transform: Multicam Clicks

*Placement:* Monitoring FX (added and removed by its action; never in renders).

Lets you click a camera in the video window to cut to it while the Multicam Switcher shows switcher view. Lives in Monitoring FX (never in renders); the Larry Seyer Video Effects - Multicam action adds it while open and removes it when closed.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `hover` | Hover outline | 1 | 0 to 1 | Outline the camera under the mouse. 0 off, 1 on. |

### LS Transform: Multicam Switcher

*Placement:* a track.

Cuts between cameras like a live switcher. Goes on a Multicam track in front of the camera tracks; its Camera envelope is the cut list and each cut can have its own transition. Switcher view shows the program with every camera underneath and the live one outlined in red. Set it up and cut with the Larry Seyer Video Effects - Multicam action (number keys or clicks in the video window).

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `cam` | Camera | 1 | 1 to 9 | Camera on air. Its envelope holds the cuts: each point switches to that camera. |
| 1 | `show` | View | 0 | 0 to 1 | Program shows the edit (what renders). Switcher shows the program with all cameras underneath, for cutting; the Multicam action sets it back to Program when you close it. Options: 0 Program, 1 Switcher. |
| 2 | `trans` | Transition | 0 | 0 to 11 | How the switch to the next camera happens. Automate it with the camera to give each cut its own transition. Options: 0 Cut, 1 Cross dissolve, 2 Dip to black, 3 Dip to white, 4 Additive dissolve, 5 Blur dissolve, 6 Luma dissolve, 7 Push, 8 Slide in, 9 Slide out, 10 Split open, 11 Squeeze. |
| 3 | `frames` | Transition frames | 12 | 1 to 120 | Length of the transition in frames. |
| 4 | `dir` | Direction | 0 | 0 to 3 | Direction for Push, Slide, Split and Squeeze. Options: 0 Left, 1 Right, 2 Up, 3 Down. |
| 5 | `ease` | Smoothness | 1 | 0 to 3 | How the transition speeds up and slows down. Options: 0 Linear, 1 Smooth, 2 Ease in, 3 Ease out. |
| 6 | `pushblur` | Motion blur | 0.5 | 0 to 1 | Motion blur for Push and Slide. |
| 7 | `source` | Source | 0 | 0 to 2 | Camera tracks: each camera on its own track, marked with a Multicam Camera effect. Multiview: one recording with the cameras in a grid, on the track directly behind. Options: 0 Camera tracks, 1 2x2 multiview, 2 3x3 multiview. |
| 8 | `trim` | Edge trim | 0.004 | 0 to 0.05 | With a multiview recording: cuts this fraction off each cell's edges to hide dividers. |
| 9 | `names` | Camera names | 1 | 0 to 1 | Show each camera's track name in switcher view. 0 off, 1 on. |

Examples:

- Straight cuts: `LS.add_to_track(track, "LS Transform: Multicam Switcher", { trans = 0 })`
- Half-second dissolves (30 fps): `LS.add_to_track(track, "LS Transform: Multicam Switcher", { trans = 1, frames = 15 })`
- Quick push to the left: `LS.add_to_track(track, "LS Transform: Multicam Switcher", { trans = 7, frames = 10, dir = 0 })`
- Switcher view while cutting: `LS.add_to_track(track, "LS Transform: Multicam Switcher", { show = 1 })`
- 2x2 multiview recording: `LS.add_to_track(track, "LS Transform: Multicam Switcher", { source = 1 })`

- Run the Larry Seyer Video Effects - Multicam action: select your camera tracks and click Set up, then play and press 1-9 or click a camera in the video window.
- Edit cuts on the Camera envelope: drag a point to move a cut, change its value to change the shot.
- Transitions play and render in order; when you jump the play cursor into one, it shows as a straight cut.

### LS Transform: Multiview Camera Select

*Placement:* an item or a track.

Turns a multiview recording (four cameras in one frame) into a multicam edit: show one camera full screen, two side by side, or one inset over another. Put it on each item and pick the camera, then crossfade items for transitions.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `cam` | Camera | 1 | 0 to 9 | Camera to show. 2x2: 1 top-left, 2 top-right, 3 bottom-left, 4 bottom-right. 0 shows the whole multiview. |
| 1 | `grid` | Multiview grid | 0 | 0 to 3 | Layout of the multiview recording. Options: 0 2x2 (4 cameras), 1 3x3 (9 cameras), 2 Side by side (2), 3 Stacked (2). |
| 2 | `zoom` | Punch in | 1 | 1 to 3 | Punch in on the chosen camera. |
| 3 | `panx` | Pan X | 0 | -1 to 1 | With punch-in: which part of that camera shows, -1 left to 1 right. |
| 4 | `pany` | Pan Y | 0 | -1 to 1 | -1 top to 1 bottom. |
| 5 | `trim` | Edge trim | 0.004 | 0 to 0.05 | Cuts this fraction off each camera's edges to hide multiview dividers. |
| 6 | `sharpen` | Sharpen | 0 | 0 to 1 | Restores crispness when a quarter is enlarged (costs speed at 4K). |
| 7 | `layout` | Layout | 0 | 0 to 2 | One camera, two side by side, or one inset over another. Options: 0 Single camera, 1 Two-up, 2 Picture-in-picture. |
| 8 | `camb` | Second camera | 2 | 1 to 9 | Second camera for Two-up and Picture-in-picture. |
| 9 | `split` | Two-up split | 0.5 | 0.2 to 0.8 | Where the two-up divides the frame. |
| 10 | `gap` | Gap | 0.006 | 0 to 0.05 | Gap between two-up panels, fraction of frame width. |
| 11 | `pipcorner` | Inset corner | 3 | 0 to 3 | Corner for the inset camera. Options: 0 Top left, 1 Top right, 2 Bottom left, 3 Bottom right. |
| 12 | `pipsize` | Inset size | 0.32 | 0.1 to 0.6 | Inset width, fraction of frame width. |

Examples:

- Camera 2 full screen: `LS.add_to_item(item, "LS Transform: Multiview Camera Select", { cam = 2 })`
- Guitar close-up from camera 1: `LS.add_to_item(item, "LS Transform: Multiview Camera Select", { cam = 1, zoom = 1.8, panx = 0.4, pany = 0.3, sharpen = 0.4 })`
- Cameras 1 and 4 side by side: `LS.add_to_item(item, "LS Transform: Multiview Camera Select", { layout = 1, cam = 1, camb = 4 })`

- Split the recording at every cut and set the camera on each item.
- Crossfade neighbouring items and put a Transition effect on the track for dissolves or pushes between cameras.

### LS Transform: Pan & Zoom

*Placement:* an item or a track.

Slow pan and zoom across a photo, screenshot or shot. Set the start and end framing; the move runs for the duration, counted from the item start (item FX) or from the start time (track FX).

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `z1` | Start zoom | 1 | 1 to 5 | Zoom at the start (1 = whole picture). |
| 1 | `x1` | Start X | 0 | -1 to 1 | Start framing: -1 left edge, 1 right edge. |
| 2 | `y1` | Start Y | 0 | -1 to 1 | Start framing: -1 top, 1 bottom. |
| 3 | `z2` | End zoom | 1.35 | 1 to 5 | Zoom at the end. |
| 4 | `x2` | End X | 0.3 | -1 to 1 | End framing, -1..1. |
| 5 | `y2` | End Y | -0.2 | -1 to 1 | End framing, -1..1. |
| 6 | `dur` | Duration (s) | 6 | 0.1 to 120 | Length of the move in seconds; set it to the item length. |
| 7 | `delay` | Start time (s) | 0 | 0 to 3600 | Track FX only: project time in seconds when the move starts. On an item the move starts at the item start. |
| 8 | `ease` | Easing | 1 | 0 to 3 | How the move speeds up and slows down. Options: 0 Linear, 1 Smooth, 2 Ease in, 3 Ease out. |

Examples:

- Slow push in on a photo: `LS.add_to_item(item, "LS Transform: Pan & Zoom", { z1 = 1, z2 = 1.25, x2 = 0, y2 = 0, dur = 8 })` Put on the photo item; set Duration to the item length.
- Pan across a wide screenshot: `LS.add_to_item(item, "LS Transform: Pan & Zoom", { z1 = 1.4, x1 = -1, y1 = 0, z2 = 1.4, x2 = 1, y2 = 0, dur = 6 })`

### LS Transform: Picture-in-Picture & Logo

*Placement:* an item or a track.

Places this clip, screenshot or logo in a corner or anywhere on screen, with rounded or circular framing, border, shadow and an entrance animated by the item fade handles.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `corner` | Corner | 8 | 0 to 8 | Where the box sits on screen. Options: 0 Top left, 1 Top, 2 Top right, 3 Left, 4 Center, 5 Right, 6 Bottom left, 7 Bottom, 8 Bottom right. |
| 1 | `size` | Size | 0.3 | 0.02 to 1 | Box width as a fraction of frame width. |
| 2 | `margin` | Margin | 0.04 | 0 to 0.3 | Gap from the frame edges, fraction of frame height. |
| 3 | `offx` | Nudge X | 0 | -1 to 1 | Fine nudge in frame widths. |
| 4 | `offy` | Nudge Y | 0 | -1 to 1 | Fine nudge in frame heights. |
| 5 | `aspect` | Aspect | 0 | 0 to 5 | Box shape. Source keeps the clip's own shape; Circle shape always uses 1:1. Options: 0 Source, 1 16:9, 2 4:3, 3 1:1, 4 9:16, 5 4:5. |
| 6 | `zoom` | Zoom inside | 1 | 1 to 4 | Zoom into the clip inside the box. |
| 7 | `panx` | Pan inside X | 0 | -1 to 1 | Which part of the clip shows when zoomed or cut to another shape: -1 left, 1 right. |
| 8 | `pany` | Pan inside Y | 0 | -1 to 1 | -1 top, 1 bottom. |
| 9 | `shape` | Shape | 1 | 0 to 2 | Rectangle, rounded rectangle or circle. Options: 0 Rectangle, 1 Rounded, 2 Circle. |
| 10 | `radius` | Corner radius | 0.12 | 0 to 0.5 | Rounding for the Rounded shape, fraction of the shorter side. |
| 11 | `border` | Border width | 0.003 | 0 to 0.03 | Border width, fraction of frame height (0 = none). |
| 12 | `bdr` | Border red | 1 | 0 to 1 | Red part of Border color (0..1). |
| 13 | `bdg` | Border green | 1 | 0 to 1 | Green part of Border color (0..1). |
| 14 | `bdb` | Border blue | 1 | 0 to 1 | Blue part of Border color (0..1). |
| 15 | `shadow` | Shadow opacity | 0.5 | 0 to 1 | Shadow strength; the shadow follows the shape and any PNG transparency. |
| 16 | `shdist` | Shadow distance | 0.008 | 0 to 0.1 | Shadow distance. |
| 17 | `shang` | Shadow angle | 120 | -180 to 180 | Shadow angle. |
| 18 | `shsoft` | Shadow softness | 0.02 | 0 to 0.1 | Shadow softness. |
| 19 | `opacity` | Opacity | 1 | 0 to 1 | Opacity. |
| 20 | `usealpha` | Use image transparency | 1 | 0 to 1 | Keep PNG transparency (logos). Turn off to show the image's transparent areas as black. 0 off, 1 on. |
| 21 | `anim` | Entrance | 1 | 0 to 5 | Entrance animation. It plays during the item fade-in and runs backwards during the fade-out. Options: 0 None, 1 Fade, 2 Slide in, 3 Pop, 4 Zoom, 5 Rise. |
| 22 | `animsrc` | Animate with | 0 | 0 to 1 | Item fades: the item's fade handles drive the animation. Manual: Manual amount does (0 hidden, 1 shown). Options: 0 Item fades, 1 Manual. |
| 23 | `amount` | Manual amount | 1 | 0 to 1 | Used when Animate with is Manual: 0 hidden, 1 fully shown. Keyframe it for custom timing. |

Examples:

- Logo bug, bottom right: `LS.add_to_item(item, "LS Transform: Picture-in-Picture & Logo", { corner = 8, size = 0.12, shape = 0, border = 0, shadow = 0.4, anim = 1, usealpha = 1 })` Put on the logo PNG item, on a track in front of the video. Give the item 0.5 s fades.
- Round webcam bubble: `LS.add_to_item(item, "LS Transform: Picture-in-Picture & Logo", { corner = 6, size = 0.22, shape = 2, border = 0.004, anim = 3 })` Put on the webcam item; use Zoom inside and Pan to frame the face.
- Screenshot card sliding in: `LS.add_to_item(item, "LS Transform: Picture-in-Picture & Logo", { corner = 4, size = 0.6, shape = 1, radius = 0.04, anim = 2 })`

- Use this instead of REAPER's stock Image overlay preset.
- If the item's fades already make a crossfade, set Animate with to Manual and keyframe Manual amount.

### LS Transform: Reframe & Letterbox

*Placement:* an item or a track.

Fits or fills the frame from any source shape, with pan for choosing what stays in view. Use it for vertical short-form video from widescreen footage, blurred-background fills, and cinematic letterbox bars.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `mode` | Mode | 0 | 0 to 2 | Fill crops to cover the frame, Fit shows the whole picture, Stretch distorts to fill. Options: 0 Fill (crop), 1 Fit (show all), 2 Stretch. |
| 1 | `panx` | Pan X | 0 | -1 to 1 | With Fill: which part stays visible, -1 left to 1 right. |
| 2 | `pany` | Pan Y | 0 | -1 to 1 | With Fill: -1 top to 1 bottom. |
| 3 | `zoom` | Zoom | 1 | 0.25 to 4 | Extra zoom on top of the fit. |
| 4 | `bgmode` | Fit background | 1 | 0 to 2 | What fills the empty area in Fit mode. Options: 0 Black, 1 Blurred copy, 2 Solid color. |
| 5 | `bgr` | Background red | 0 | 0 to 1 | Red part of Background color (0..1). |
| 6 | `bgg` | Background green | 0 | 0 to 1 | Green part of Background color (0..1). |
| 7 | `bgb` | Background blue | 0 | 0 to 1 | Blue part of Background color (0..1). |
| 8 | `bars` | Letterbox bars | 0 | 0 to 5 | Cinematic bars drawn over the picture. Options: 0 None, 1 2.39:1 Cinemascope, 2 2:1, 3 1.85:1, 4 4:3, 5 1:1. |
| 9 | `baropacity` | Bar opacity | 1 | 0 to 1 | Bar darkness. |

Examples:

- Vertical Short from 16:9 footage: `LS.add_to_item(item, "LS Transform: Reframe & Letterbox", { mode = 0, panx = 0 })` Set the project video size to 1080x1920 first; keyframe Pan X to follow the action.
- Fit with blurred background: `LS.add_to_item(item, "LS Transform: Reframe & Letterbox", { mode = 1, bgmode = 1 })`
- Cinemascope bars: `LS.add_to_item(item, "LS Transform: Reframe & Letterbox", { mode = 0, bars = 1 })`

### LS Transform: Transform

*Placement:* an item or a track.

Position, scale, rotate, crop, round corners, border and drop shadow in one pass. Keyframe any control with envelopes.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `posx` | Position X | 0 | -1.5 to 1.5 | Horizontal offset in frame widths: 0 centered, 0.5 moves it half a frame right. |
| 1 | `posy` | Position Y | 0 | -1.5 to 1.5 | Vertical offset in frame heights: positive moves down. |
| 2 | `scale` | Scale | 1 | 0 to 5 | Size relative to the whole picture fitting the frame: 1 fits, 0.5 is half size. |
| 3 | `stx` | Stretch X | 1 | 0.1 to 4 | Extra horizontal stretch (1 = none). |
| 4 | `sty` | Stretch Y | 1 | 0.1 to 4 | Extra vertical stretch (1 = none). |
| 5 | `rot` | Rotation | 0 | -720 to 720 | Rotation in degrees, clockwise. |
| 6 | `ancx` | Anchor X | 0 | -1 to 1 | Pivot for rotate and scale: -1 left edge, 0 center, 1 right edge of the picture. |
| 7 | `ancy` | Anchor Y | 0 | -1 to 1 | Pivot for rotate and scale: -1 top edge, 0 center, 1 bottom edge of the picture. |
| 8 | `cl` | Crop left | 0 | 0 to 0.95 | Fraction of the picture cut off the left. Cropping does not re-center the picture. |
| 9 | `cr` | Crop right | 0 | 0 to 0.95 | Fraction cut off the right. |
| 10 | `ct` | Crop top | 0 | 0 to 0.95 | Fraction cut off the top. |
| 11 | `cb` | Crop bottom | 0 | 0 to 0.95 | Fraction cut off the bottom. |
| 12 | `opacity` | Opacity | 1 | 0 to 1 | 0 invisible, 1 solid. |
| 13 | `fliph` | Flip horizontal | 0 | 0 to 1 | 0 off, 1 on. |
| 14 | `flipv` | Flip vertical | 0 | 0 to 1 | 0 off, 1 on. |
| 15 | `radius` | Corner radius | 0 | 0 to 0.5 | Corner rounding as a fraction of the shorter side; 0.5 makes a pill or circle. |
| 16 | `border` | Border width | 0 | 0 to 0.05 | Border width as a fraction of frame height (0.005 is a thin line at any resolution). |
| 17 | `bdr` | Border red | 1 | 0 to 1 | Red part of Border color (0..1). |
| 18 | `bdg` | Border green | 1 | 0 to 1 | Green part of Border color (0..1). |
| 19 | `bdb` | Border blue | 1 | 0 to 1 | Blue part of Border color (0..1). |
| 20 | `shadow` | Shadow opacity | 0 | 0 to 1 | Drop shadow strength (0 = off). |
| 21 | `shdist` | Shadow distance | 0.012 | 0 to 0.1 | Shadow offset, fraction of frame height. |
| 22 | `shang` | Shadow angle | 135 | -180 to 180 | Direction the shadow falls in degrees: 90 straight down, 135 down-left, 45 down-right. |
| 23 | `shsoft` | Shadow softness | 0.02 | 0 to 0.1 | Blur of the shadow edge, fraction of frame height. |
| 24 | `bgmode` | Background | 0 | 0 to 3 | What shows around the picture when it is smaller than the frame. Options: 0 Tracks behind, 1 Black, 2 Blurred copy, 3 Solid color. |
| 25 | `bgr` | Background red | 0 | 0 to 1 | Red part of Background color (0..1). |
| 26 | `bgg` | Background green | 0 | 0 to 1 | Green part of Background color (0..1). |
| 27 | `bgb` | Background blue | 0 | 0 to 1 | Blue part of Background color (0..1). |

Examples:

- Picture-in-picture, top right: `LS.add_to_item(item, "LS Transform: Transform", { scale = 0.35, posx = 0.3, posy = -0.28, radius = 0.06, border = 0.004, shadow = 0.6 })` Put on the inset clip's item, on a track in front of the main video.
- Tilted card: `LS.add_to_item(item, "LS Transform: Transform", { scale = 0.6, rot = -6, radius = 0.05, border = 0.006, shadow = 0.7 })`
- Animated zoom-out: `LS.add_to_item(item, "LS Transform: Transform", { scale = 1.5 })` Keyframe Scale at 1.5 at the item start and 1 two seconds later.

- On an item it changes only that clip; on a track it changes everything on the track.
- For moves, keyframe Position, Scale and Rotation; the keyframes are ordinary REAPER envelopes.

### LS Transform: Zoom to Region

*Placement:* an item or a track.

Smoothly zooms into a chosen rectangle, ideal for showing a control in a screen recording. Drag the item fade-in and fade-out to set how long the zoom in and out take, or automate the amount.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `rx` | Region left | 0.3 | 0 to 1 | Left edge of the zoom region, fraction of the picture width. |
| 1 | `ry` | Region top | 0.3 | 0 to 1 | Top edge, fraction of picture height. |
| 2 | `rw` | Region width | 0.4 | 0.02 to 1 | Region width, fraction of picture width. |
| 3 | `rh` | Region height | 0.4 | 0.02 to 1 | Region height, fraction of picture height. |
| 4 | `animsrc` | Animate with | 0 | 0 to 1 | Item fades: zooms in over the fade-in and out over the fade-out. Manual: Manual amount controls it. Options: 0 Item fades, 1 Manual. |
| 5 | `amount` | Manual amount | 1 | 0 to 1 | Manual mode: 0 whole picture, 1 zoomed into the region. |
| 6 | `ease` | Easing | 1 | 0 to 3 | Options: 0 Linear, 1 Smooth, 2 Ease in, 3 Ease out. |
| 7 | `showbox` | Show region outline | 0 | 0 to 1 | Draws the region outline while you set it up. Turn it off before rendering. 0 off, 1 on. |

Examples:

- Zoom into a control: `LS.add_to_item(item, "LS Transform: Zoom to Region", { rx = 0.05, ry = 0.1, rw = 0.3, rh = 0.2, animsrc = 0 })` Split the screen recording so one item covers the zoom; its fade-in is the zoom-in time, its fade-out the zoom-out time.

- The region is grown to the frame shape so the picture never stretches.
- If the item's fades already make a crossfade, set Animate with to Manual and keyframe Manual amount.
- The region grows around its center to the frame shape. A tall strip (such as the whole right half) grows back to the full frame and does not zoom; for 2x on the right half use left 0.5, top 0.25, width 0.5, height 0.5.

### LS Color: Color Grade

*Placement:* an item or a track.

Primary color grading: lift, gamma, gain and offset wheels, temperature and tint, contrast with pivot, saturation, vibrance, exposure, shadows and highlights, with a before/after split.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `liftr` | Lift red | 0 | -0.5 to 0.5 | Red offset of the Lift wheel. Lift wheel: color of the shadows. The wheel's red, green and blue values are offsets; pushing toward one color raises it and lowers the others. |
| 1 | `liftg` | Lift green | 0 | -0.5 to 0.5 | Green offset of the Lift wheel. Lift wheel: color of the shadows. The wheel's red, green and blue values are offsets; pushing toward one color raises it and lowers the others. |
| 2 | `liftb` | Lift blue | 0 | -0.5 to 0.5 | Blue offset of the Lift wheel. Lift wheel: color of the shadows. The wheel's red, green and blue values are offsets; pushing toward one color raises it and lowers the others. |
| 3 | `liftm` | Lift master | 0 | -0.5 to 0.5 | Raises (positive) or lowers the black level. |
| 4 | `gamr` | Gamma red | 0 | -1 to 1 | Red offset of the Gamma wheel. Gamma wheel: color of the midtones. |
| 5 | `gamg` | Gamma green | 0 | -1 to 1 | Green offset of the Gamma wheel. Gamma wheel: color of the midtones. |
| 6 | `gamb` | Gamma blue | 0 | -1 to 1 | Blue offset of the Gamma wheel. Gamma wheel: color of the midtones. |
| 7 | `gamm` | Gamma master | 0 | -1 to 1 | Brightens (positive) or darkens the midtones. |
| 8 | `gainr` | Gain red | 0 | -0.5 to 0.5 | Red offset of the Gain wheel. Gain wheel: color of the highlights. |
| 9 | `gaing` | Gain green | 0 | -0.5 to 0.5 | Green offset of the Gain wheel. Gain wheel: color of the highlights. |
| 10 | `gainb` | Gain blue | 0 | -0.5 to 0.5 | Blue offset of the Gain wheel. Gain wheel: color of the highlights. |
| 11 | `gainm` | Gain master | 1 | 0 to 2 | Overall brightness multiplier (1 = unchanged). |
| 12 | `offr` | Offset red | 0 | -0.2 to 0.2 | Red offset of the Offset wheel. Offset wheel: shifts all tones equally. |
| 13 | `offg` | Offset green | 0 | -0.2 to 0.2 | Green offset of the Offset wheel. Offset wheel: shifts all tones equally. |
| 14 | `offb` | Offset blue | 0 | -0.2 to 0.2 | Blue offset of the Offset wheel. Offset wheel: shifts all tones equally. |
| 15 | `offm` | Offset master | 0 | -0.2 to 0.2 | Shifts everything brighter or darker. |
| 16 | `contrast` | Contrast | 1 | 0 to 2 | 1 unchanged; above 1 more contrast. |
| 17 | `pivot` | Pivot | 0.435 | 0 to 1 | Tone that contrast pivots around (0.435 is video mid-gray). |
| 18 | `sat` | Saturation | 1 | 0 to 2 | Saturation; 0 is black and white. |
| 19 | `vib` | Vibrance | 0 | -1 to 1 | Boosts muted colors more than strong ones, protecting skin tones. |
| 20 | `temp` | Temperature | 0 | -1 to 1 | Negative cooler (blue), positive warmer (orange). |
| 21 | `tint` | Tint | 0 | -1 to 1 | Negative green, positive magenta. |
| 22 | `hue` | Hue rotate | 0 | -180 to 180 | Rotates every color around the color wheel, in degrees. |
| 23 | `exposure` | Exposure (stops) | 0 | -3 to 3 | Brightness in photographic stops. |
| 24 | `shadows` | Shadows | 0 | -1 to 1 | Lifts (positive) or deepens dark areas only. |
| 25 | `highlights` | Highlights | 0 | -1 to 1 | Recovers (negative) or boosts bright areas. |
| 26 | `mix` | Mix | 1 | 0 to 1 | Blend with the original (1 = full effect). |
| 27 | `split` | Before/after split | 0 | 0 to 1 | Shows the original on the left half for comparison. Turn off before rendering. 0 off, 1 on. |

Examples:

- Warm stage look: `LS.add_to_item(item, "LS Color: Color Grade", { temp = 0.25, sat = 1.1, contrast = 1.1 })`
- Teal shadows, warm highlights: `LS.add_to_item(item, "LS Color: Color Grade", { liftr = -0.02, liftb = 0.04, gainr = 0.06, gainb = -0.05, contrast = 1.1 })`
- Rescue a dark recording: `LS.add_to_item(item, "LS Color: Color Grade", { exposure = 0.5, shadows = 0.3 })`

- Temperature, tint, contrast, exposure and the wheels are very fast. Hue rotate and vibrance are slower at 4K.
- Subtle: temperature 0.1-0.2, saturation 1.05-1.15. Strong: temperature 0.4, saturation 1.3.

### LS Color: Curves

*Placement:* an item or a track.

Custom curves: a master curve plus red, green and blue curves, each with seven points you drag in the panel.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `cm0` | Master 0% | 0 | 0 to 1 | Master curve output at input 0%. Each curve has seven points at input 0%, 17%, 33%, 50%, 67%, 83%, 100%; a point's value is the output (0..1). Equal values mean no change. |
| 1 | `cm1` | Master 17% | 0.1667 | 0 to 1 | Master curve output at input 17%. Each curve has seven points at input 0%, 17%, 33%, 50%, 67%, 83%, 100%; a point's value is the output (0..1). Equal values mean no change. |
| 2 | `cm2` | Master 33% | 0.3333 | 0 to 1 | Master curve output at input 33%. Each curve has seven points at input 0%, 17%, 33%, 50%, 67%, 83%, 100%; a point's value is the output (0..1). Equal values mean no change. |
| 3 | `cm3` | Master 50% | 0.5 | 0 to 1 | Master curve output at input 50%. Each curve has seven points at input 0%, 17%, 33%, 50%, 67%, 83%, 100%; a point's value is the output (0..1). Equal values mean no change. |
| 4 | `cm4` | Master 67% | 0.6667 | 0 to 1 | Master curve output at input 67%. Each curve has seven points at input 0%, 17%, 33%, 50%, 67%, 83%, 100%; a point's value is the output (0..1). Equal values mean no change. |
| 5 | `cm5` | Master 83% | 0.8333 | 0 to 1 | Master curve output at input 83%. Each curve has seven points at input 0%, 17%, 33%, 50%, 67%, 83%, 100%; a point's value is the output (0..1). Equal values mean no change. |
| 6 | `cm6` | Master 100% | 1 | 0 to 1 | Master curve output at input 100%. Each curve has seven points at input 0%, 17%, 33%, 50%, 67%, 83%, 100%; a point's value is the output (0..1). Equal values mean no change. |
| 7 | `cr0` | Red 0% | 0 | 0 to 1 | Red curve output at input 0%. |
| 8 | `cr1` | Red 17% | 0.1667 | 0 to 1 | Red curve output at input 17%. |
| 9 | `cr2` | Red 33% | 0.3333 | 0 to 1 | Red curve output at input 33%. |
| 10 | `cr3` | Red 50% | 0.5 | 0 to 1 | Red curve output at input 50%. |
| 11 | `cr4` | Red 67% | 0.6667 | 0 to 1 | Red curve output at input 67%. |
| 12 | `cr5` | Red 83% | 0.8333 | 0 to 1 | Red curve output at input 83%. |
| 13 | `cr6` | Red 100% | 1 | 0 to 1 | Red curve output at input 100%. |
| 14 | `cg0` | Green 0% | 0 | 0 to 1 | Green curve output at input 0%. |
| 15 | `cg1` | Green 17% | 0.1667 | 0 to 1 | Green curve output at input 17%. |
| 16 | `cg2` | Green 33% | 0.3333 | 0 to 1 | Green curve output at input 33%. |
| 17 | `cg3` | Green 50% | 0.5 | 0 to 1 | Green curve output at input 50%. |
| 18 | `cg4` | Green 67% | 0.6667 | 0 to 1 | Green curve output at input 67%. |
| 19 | `cg5` | Green 83% | 0.8333 | 0 to 1 | Green curve output at input 83%. |
| 20 | `cg6` | Green 100% | 1 | 0 to 1 | Green curve output at input 100%. |
| 21 | `cb0` | Blue 0% | 0 | 0 to 1 | Blue curve output at input 0%. |
| 22 | `cb1` | Blue 17% | 0.1667 | 0 to 1 | Blue curve output at input 17%. |
| 23 | `cb2` | Blue 33% | 0.3333 | 0 to 1 | Blue curve output at input 33%. |
| 24 | `cb3` | Blue 50% | 0.5 | 0 to 1 | Blue curve output at input 50%. |
| 25 | `cb4` | Blue 67% | 0.6667 | 0 to 1 | Blue curve output at input 67%. |
| 26 | `cb5` | Blue 83% | 0.8333 | 0 to 1 | Blue curve output at input 83%. |
| 27 | `cb6` | Blue 100% | 1 | 0 to 1 | Blue curve output at input 100%. |
| 28 | `mix` | Mix | 1 | 0 to 1 | Blend with the original. |

Examples:

- Gentle S-curve: `LS.add_to_item(item, "LS Color: Curves", { cm1 = 0.12, cm2 = 0.29, cm4 = 0.71, cm5 = 0.88 })`
- Faded blacks: `LS.add_to_item(item, "LS Color: Curves", { cm0 = 0.08 })`
- Warmer highlights: `LS.add_to_item(item, "LS Color: Curves", { cr5 = 0.86, cr6 = 1, cb5 = 0.8, cb6 = 0.95 })`

- The channel curves (red, green, blue) are applied first, then the master curve.

### LS Color: Hue Curves

*Placement:* an item or a track.

Hue curves: shift the hue, saturation or brightness of each color range separately, plus saturation by brightness.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `hh0` | Red hue shift | 0 | -60 to 60 | Hue vs Hue shift for red. Hue shift in degrees for each color range: index 0 red, 1 yellow, 2 green, 3 cyan, 4 blue, 5 magenta. |
| 1 | `hh1` | Yellow hue shift | 0 | -60 to 60 | Hue vs Hue shift for yellow. Hue shift in degrees for each color range: index 0 red, 1 yellow, 2 green, 3 cyan, 4 blue, 5 magenta. |
| 2 | `hh2` | Green hue shift | 0 | -60 to 60 | Hue vs Hue shift for green. Hue shift in degrees for each color range: index 0 red, 1 yellow, 2 green, 3 cyan, 4 blue, 5 magenta. |
| 3 | `hh3` | Cyan hue shift | 0 | -60 to 60 | Hue vs Hue shift for cyan. Hue shift in degrees for each color range: index 0 red, 1 yellow, 2 green, 3 cyan, 4 blue, 5 magenta. |
| 4 | `hh4` | Blue hue shift | 0 | -60 to 60 | Hue vs Hue shift for blue. Hue shift in degrees for each color range: index 0 red, 1 yellow, 2 green, 3 cyan, 4 blue, 5 magenta. |
| 5 | `hh5` | Magenta hue shift | 0 | -60 to 60 | Hue vs Hue shift for magenta. Hue shift in degrees for each color range: index 0 red, 1 yellow, 2 green, 3 cyan, 4 blue, 5 magenta. |
| 6 | `hs0` | Red saturation | 1 | 0 to 2 | Hue vs Saturation for red. Saturation multiplier per color range (same order; 1 unchanged). |
| 7 | `hs1` | Yellow saturation | 1 | 0 to 2 | Hue vs Saturation for yellow. Saturation multiplier per color range (same order; 1 unchanged). |
| 8 | `hs2` | Green saturation | 1 | 0 to 2 | Hue vs Saturation for green. Saturation multiplier per color range (same order; 1 unchanged). |
| 9 | `hs3` | Cyan saturation | 1 | 0 to 2 | Hue vs Saturation for cyan. Saturation multiplier per color range (same order; 1 unchanged). |
| 10 | `hs4` | Blue saturation | 1 | 0 to 2 | Hue vs Saturation for blue. Saturation multiplier per color range (same order; 1 unchanged). |
| 11 | `hs5` | Magenta saturation | 1 | 0 to 2 | Hue vs Saturation for magenta. Saturation multiplier per color range (same order; 1 unchanged). |
| 12 | `hl0` | Red brightness | 0 | -0.3 to 0.3 | Hue vs Brightness for red. Brightness offset per color range (same order). |
| 13 | `hl1` | Yellow brightness | 0 | -0.3 to 0.3 | Hue vs Brightness for yellow. Brightness offset per color range (same order). |
| 14 | `hl2` | Green brightness | 0 | -0.3 to 0.3 | Hue vs Brightness for green. Brightness offset per color range (same order). |
| 15 | `hl3` | Cyan brightness | 0 | -0.3 to 0.3 | Hue vs Brightness for cyan. Brightness offset per color range (same order). |
| 16 | `hl4` | Blue brightness | 0 | -0.3 to 0.3 | Hue vs Brightness for blue. Brightness offset per color range (same order). |
| 17 | `hl5` | Magenta brightness | 0 | -0.3 to 0.3 | Hue vs Brightness for magenta. Brightness offset per color range (same order). |
| 18 | `ls0` | Shadow saturation | 1 | 0 to 2 | Saturation of dark areas. |
| 19 | `ls1` | Midtone saturation | 1 | 0 to 2 | Saturation of midtones. |
| 20 | `ls2` | Highlight saturation | 1 | 0 to 2 | Saturation of bright areas. |
| 21 | `mix` | Mix | 1 | 0 to 1 | Blend with the original. |

Examples:

- Calm down greens: `LS.add_to_item(item, "LS Color: Hue Curves", { hs2 = 0.4 })`
- Push oranges toward red: `LS.add_to_item(item, "LS Color: Hue Curves", { hh1 = -10 })`
- Desaturate the shadows: `LS.add_to_item(item, "LS Color: Hue Curves", { ls0 = 0.4 })`

### LS Color: Isolate Color

*Placement:* an item or a track.

Picks one color range and changes it on its own, or keeps it while the rest of the picture goes black and white for a color-pop look.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `selhue` | Hue | 0 | 0 to 360 | Color to select in degrees: 0 red, 30 orange, 60 yellow, 120 green, 180 cyan, 240 blue, 300 magenta. |
| 1 | `width` | Hue width | 30 | 2 to 180 | How wide a range of hues counts as selected. |
| 2 | `soft` | Softness | 20 | 0 to 90 | Softness of the selection edge in degrees. |
| 3 | `satmin` | Min saturation | 0.2 | 0 to 1 | Ignore pale colors below this saturation. |
| 4 | `lummin` | Min brightness | 0 | 0 to 1 | Ignore pixels darker than this. |
| 5 | `lummax` | Max brightness | 1 | 0 to 1 | Ignore pixels brighter than this. |
| 6 | `ihue` | Inside hue shift | 0 | -180 to 180 | Hue shift for the selected color. |
| 7 | `isat` | Inside saturation | 1.2 | 0 to 2 | Saturation of the selected color. |
| 8 | `ilum` | Inside brightness | 0 | -0.5 to 0.5 | Brightness change for the selected color. |
| 9 | `osat` | Outside saturation | 0 | 0 to 2 | Saturation of everything else: 0 makes it black and white (color pop). |
| 10 | `olum` | Outside brightness | 0 | -0.5 to 0.5 | Brightness change for everything else. |
| 11 | `invert` | Invert selection | 0 | 0 to 1 | Swap selected and unselected. 0 off, 1 on. |
| 12 | `showmask` | Show selection | 0 | 0 to 1 | Shows the selection in white. Turn off before rendering. 0 off, 1 on. |
| 13 | `mix` | Mix | 1 | 0 to 1 | Blend with the original. |

Examples:

- Color pop: keep only reds: `LS.add_to_item(item, "LS Color: Isolate Color", { selhue = 0, width = 30, osat = 0 })`
- Turn a red guitar blue: `LS.add_to_item(item, "LS Color: Isolate Color", { selhue = 0, width = 40, ihue = -120, osat = 1 })`

- Turn on Show selection while adjusting Hue, Hue width and Min saturation.

### LS Color: Looks

*Placement:* an item or a track.

One-knob film and music-video looks: black and white, sepia, teal and orange, warm film, cool night, bleach bypass, faded vintage, cross process, punch, golden hour, noir and duotone.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `look` | Look | 2 | 0 to 11 | The look. Options: 0 Black & White, 1 Sepia, 2 Teal & Orange, 3 Warm Film, 4 Cool Night, 5 Bleach Bypass, 6 Faded Vintage, 7 Cross Process, 8 Punch, 9 Golden Hour, 10 Noir, 11 Duotone. |
| 1 | `amount` | Amount | 1 | 0 to 1 | Blend with the original. |
| 2 | `strength` | Contrast | 1 | 0 to 2 | Contrast multiplier for the look. |
| 3 | `bwr` | B&W red weight | 0.3 | -1 to 2 | Black and white mix: how much red contributes (used by Black & White, Sepia and Noir). |
| 4 | `bwg` | B&W green weight | 0.59 | -1 to 2 | How much green contributes. |
| 5 | `bwb` | B&W blue weight | 0.11 | -1 to 2 | How much blue contributes. |
| 6 | `dsr` | Duotone shadow red | 0.08 | 0 to 1 | Red part of Duotone shadows (0..1). |
| 7 | `dsg` | Duotone shadow green | 0.07 | 0 to 1 | Green part of Duotone shadows (0..1). |
| 8 | `dsb` | Duotone shadow blue | 0.3 | 0 to 1 | Blue part of Duotone shadows (0..1). |
| 9 | `dhr` | Duotone highlight red | 1 | 0 to 1 | Red part of Duotone highlights (0..1). |
| 10 | `dhg` | Duotone highlight green | 0.78 | 0 to 1 | Green part of Duotone highlights (0..1). |
| 11 | `dhb` | Duotone highlight blue | 0.45 | 0 to 1 | Blue part of Duotone highlights (0..1). |

Examples:

- Teal and orange: `LS.add_to_item(item, "LS Color: Looks", { look = 2 })`
- Black and white: `LS.add_to_item(item, "LS Color: Looks", { look = 0 })`
- Duotone in brand colors: `LS.add_to_item(item, "LS Color: Looks", { look = 11, dsr = 0.05, dsg = 0.1, dsb = 0.12, dhr = 0.24, dhg = 0.87, dhb = 0.66 })`

### LS Color: Vignette

*Placement:* an item or a track.

Darkens (or tints) the edges of the frame to pull the eye to the center, with adjustable size, softness, shape and center.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `amount` | Amount | 0.5 | 0 to 1 | Strength at the edges. |
| 1 | `size` | Size | 1 | 0.1 to 2 | Where the darkening is complete; 1 reaches the edges. |
| 2 | `soft` | Softness | 0.7 | 0.01 to 1 | Width of the transition. |
| 3 | `round` | Roundness | 0.5 | 0 to 1 | 0 follows the frame shape, 1 is circular. |
| 4 | `cx` | Center X | 0 | -1 to 1 | Center, -1 left to 1 right. |
| 5 | `cy` | Center Y | 0 | -1 to 1 | Center, -1 top to 1 bottom. |
| 6 | `vr` | Color red | 0 | 0 to 1 | Red part of Color (0..1). |
| 7 | `vg` | Color green | 0 | 0 to 1 | Green part of Color (0..1). |
| 8 | `vb` | Color blue | 0 | 0 to 1 | Blue part of Color (0..1). |

Examples:

- Subtle: `LS.add_to_item(item, "LS Color: Vignette", { amount = 0.35 })`
- White dreamy edges: `LS.add_to_item(item, "LS Color: Vignette", { vr = 1, vg = 1, vb = 1, amount = 0.5 })`

### LS Look: Beat Pulse

*Placement:* an item or a track.

Punches the picture in time with the music using the project tempo: zoom kicks, light flashes, color split and shake on every beat, half beat or bar.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `division` | Pulse on | 2 | 0 to 4 | How often it pulses, using the project tempo. Options: 0 Every bar, 1 Every 2 beats, 2 Every beat, 3 Every 1/2 beat, 4 Every 1/4 beat. |
| 1 | `decay` | Decay | 0.35 | 0.02 to 1 | How fast each pulse fades, as a fraction of the interval. |
| 2 | `offset` | Offset (beats) | 0 | -0.5 to 0.5 | Moves pulses earlier or later, in beats. |
| 3 | `zoom` | Zoom kick | 0.05 | 0 to 0.3 | Zoom kick size. |
| 4 | `flash` | Flash | 0.25 | 0 to 1 | Light flash strength. |
| 5 | `rgb` | Color split | 0 | 0 to 1 | Color split on the hit. |
| 6 | `shake` | Shake | 0 | 0 to 1 | Shake on the hit. |
| 7 | `fr` | Flash red | 1 | 0 to 1 | Red part of Flash color (0..1). |
| 8 | `fg` | Flash green | 1 | 0 to 1 | Green part of Flash color (0..1). |
| 9 | `fb` | Flash blue | 1 | 0 to 1 | Blue part of Flash color (0..1). |

Examples:

- Kick on every beat: `LS.add_to_item(item, "LS Look: Beat Pulse", { division = 2, zoom = 0.05, flash = 0.2 })`
- Bar accents: `LS.add_to_item(item, "LS Look: Beat Pulse", { division = 0, zoom = 0.1, flash = 0.5, rgb = 0.5 })`

- Uses the project tempo and time signature: set them to match the song.

### LS Look: Echo Trails

*Placement:* an item or a track.

Moving subjects leave fading echoes behind them, with optional zoom or spin drift for psychedelic tunnels.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `persist` | Trail length | 0.8 | 0 to 0.98 | Trail length (0 none, 0.95 very long). |
| 1 | `mode` | Mode | 0 | 0 to 1 | Blend smears; Additive glow brightens overlapping trails. Options: 0 Blend, 1 Additive glow. |
| 2 | `drift` | Zoom drift | 0 | -0.05 to 0.05 | Trails zoom in or out over time. |
| 3 | `spin` | Spin drift | 0 | -5 to 5 | Trails rotate over time, degrees per frame. |

Examples:

- Dreamy echoes: `LS.add_to_item(item, "LS Look: Echo Trails", { persist = 0.85 })`
- Psychedelic tunnel: `LS.add_to_item(item, "LS Look: Echo Trails", { persist = 0.9, mode = 1, drift = 0.01, spin = 1 })`

### LS Look: Film Look

*Placement:* an item or a track.

Film grain, gate weave, flicker, dust and scratches, faded blacks, warmth, vignette and optional widescreen bars.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `grain` | Grain | 0.25 | 0 to 1 | Grain strength. |
| 1 | `grainsize` | Grain size | 1.5 | 1 to 4 | Grain size in pixels at 1080p. |
| 2 | `weave` | Gate weave | 0.3 | 0 to 1 | Frame wobble like a film projector. |
| 3 | `flicker` | Flicker | 0.2 | 0 to 1 | Brightness flicker. |
| 4 | `dust` | Dust & scratches | 0.3 | 0 to 1 | Dust specks and occasional scratches. |
| 5 | `fade` | Faded blacks | 0.08 | 0 to 0.4 | Lifts black to this level. |
| 6 | `warmth` | Warmth | 0.2 | -1 to 1 | Negative cooler, positive warmer. |
| 7 | `vig` | Vignette | 0.35 | 0 to 1 | Edge darkening. |
| 8 | `bars` | Bars | 0 | 0 to 2 | Widescreen bars. Options: 0 None, 1 2.39:1, 2 1.85:1. |

Examples:

- Vintage film: `LS.add_to_item(item, "LS Look: Film Look", { grain = 0.35, dust = 0.5, fade = 0.12, warmth = 0.4 })`
- Clean cinematic: `LS.add_to_item(item, "LS Look: Film Look", { grain = 0.15, weave = 0, flicker = 0, dust = 0, bars = 1 })`

### LS Look: Glitch

*Placement:* an item or a track.

Digital breakup: torn slices, displaced blocks and color splitting. Automate the amount for hits, or lock bursts to the beat.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `amount` | Amount | 0.5 | 0 to 1 | Overall strength; keyframe it for hits. |
| 1 | `slices` | Slice tearing | 0.6 | 0 to 1 | Torn horizontal slices. |
| 2 | `blocks` | Block displacement | 0.5 | 0 to 1 | Displaced rectangles. |
| 3 | `rgb` | Color split | 0.6 | 0 to 1 | Color channel splitting. |
| 4 | `speed` | Changes per second | 12 | 1 to 30 | How often the glitch pattern changes per second. |
| 5 | `beatsync` | Burst on each beat | 0 | 0 to 1 | Bursts on every beat of the project tempo. 0 off, 1 on. |
| 6 | `seed` | Seed | 1 | 0 to 100 | Changes the random pattern. |

Examples:

- Glitch on the beat: `LS.add_to_item(item, "LS Look: Glitch", { amount = 0.7, beatsync = 1 })` Set the project tempo to the song first.

### LS Look: Glow & Bloom

*Placement:* an item or a track.

Bright parts bloom into a soft glow, or the whole image gets a dreamy diffusion like a mist filter.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `mode` | Mode | 0 | 0 to 1 | Bloom glows only bright areas; Soft diffusion blends a soft copy over everything (mist filter). Options: 0 Bloom, 1 Soft diffusion. |
| 1 | `intensity` | Intensity | 0.6 | 0 to 2 | Glow strength. |
| 2 | `thresh` | Threshold | 0.65 | 0 to 1 | Bloom: only parts brighter than this glow. |
| 3 | `radius` | Size | 0.5 | 0 to 1 | Glow size. |
| 4 | `tr` | Tint red | 1 | 0 to 1 | Red part of Tint (0..1). |
| 5 | `tg` | Tint green | 1 | 0 to 1 | Green part of Tint (0..1). |
| 6 | `tb` | Tint blue | 1 | 0 to 1 | Blue part of Tint (0..1). |

Examples:

- Stage light bloom: `LS.add_to_item(item, "LS Look: Glow & Bloom", { mode = 0, intensity = 0.8, thresh = 0.6 })`
- Mist filter: `LS.add_to_item(item, "LS Look: Glow & Bloom", { mode = 1, intensity = 0.6 })`

### LS Look: Sharpen & Soften

*Placement:* an item or a track.

Crisps up soft or upscaled footage, or softens it for a gentler, diffused look. Positive amounts sharpen, negative amounts soften.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `amount` | Amount | 0.5 | -1 to 2 | Positive sharpens, negative softens. |
| 1 | `radius` | Radius | 1 | 1 to 4 | Size of the detail affected (1 fine to 4 coarse). |
| 2 | `thresh` | Threshold | 0.02 | 0 to 0.2 | Ignores differences below this so noise is not sharpened. |

Examples:

- Crisp up upscaled footage: `LS.add_to_item(item, "LS Look: Sharpen & Soften", { amount = 0.8, radius = 1 })`
- Soft dreamy: `LS.add_to_item(item, "LS Look: Sharpen & Soften", { amount = -0.6, radius = 3 })`

### LS Look: VHS & Retro TV

*Placement:* an item or a track.

Worn videotape: color bleed, soft picture, scanlines, noise, rolling tracking glitches and an optional PLAY label.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `bleed` | Color bleed | 0.5 | 0 to 1 | Color fringing. |
| 1 | `soften` | Softness | 0.5 | 0 to 1 | Horizontal smear like tape. |
| 2 | `scan` | Scanlines | 0.3 | 0 to 1 | Scanline darkness. |
| 3 | `noise` | Noise | 0.25 | 0 to 1 | Noise. |
| 4 | `track` | Tracking | 0.4 | 0 to 1 | Rolling tracking glitch band. |
| 5 | `desat` | Washed out | 0.25 | 0 to 1 | Washed-out color. |
| 6 | `label` | PLAY label | 1 | 0 to 1 | Shows a PLAY label in the corner. 0 off, 1 on. |

Examples:

- Home video flashback: `LS.add_to_item(item, "LS Look: VHS & Retro TV", { bleed = 0.6, track = 0.5, label = 1 })`

### LS Look: Zoom & Motion Blur

*Placement:* an item or a track.

Radial zoom blur bursting from a point, or directional blur that streaks the picture at any angle.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `mode` | Mode | 0 | 0 to 1 | Zoom blurs outward from a point; Directional streaks along an angle. Options: 0 Zoom, 1 Directional. |
| 1 | `amount` | Amount | 0.3 | 0 to 1 | Blur strength. |
| 2 | `cx` | Center X | 0 | -1 to 1 | Zoom center, -1 left to 1 right. |
| 3 | `cy` | Center Y | 0 | -1 to 1 | Zoom center, -1 top to 1 bottom. |
| 4 | `angle` | Angle | 0 | -180 to 180 | Directional angle in degrees. |
| 5 | `quality` | Quality | 16 | 4 to 32 | More samples look smoother but are slower. |

Examples:

- Burst from center: `LS.add_to_item(item, "LS Look: Zoom & Motion Blur", { mode = 0, amount = 0.5 })`

### LS Transition: Dissolve & Dip

*Placement:* a track.

Put on a track: every crossfade between items on that track becomes this transition, lasting as long as the crossfade. Cross dissolve, dip to black, white or a color, additive, blur and luma dissolves.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `style` | Style | 0 | 0 to 6 | Kind of dissolve. Options: 0 Cross dissolve, 1 Dip to black, 2 Dip to white, 3 Dip to color, 4 Additive dissolve, 5 Blur dissolve, 6 Luma dissolve. |
| 1 | `ease` | Smoothness | 1 | 0 to 3 | How the transition speeds up and slows down. Options: 0 Linear, 1 Smooth, 2 Ease in, 3 Ease out. |
| 2 | `dcr` | Dip red | 0.2 | 0 to 1 | Red part of Dip color (0..1). |
| 3 | `dcg` | Dip green | 0.6 | 0 to 1 | Green part of Dip color (0..1). |
| 4 | `dcb` | Dip blue | 0.9 | 0 to 1 | Blue part of Dip color (0..1). |
| 5 | `srcmode` | Source | 0 | 0 to 1 | Item crossfades: runs on every crossfade between items on this track. Manual: blends this track into the next track behind it using Manual progress. Options: 0 Item crossfades, 1 Manual (this track to the one behind). |
| 6 | `progress` | Manual progress | 0 | 0 to 1 | Manual mode: 0 shows this track, 1 the track behind. Keyframe 0 to 1 over the transition. |
| 7 | `reverse` | Reverse | 0 | 0 to 1 | Swap outgoing and incoming (use if a direction comes out backwards). 0 off, 1 on. |

Examples:

- Cross dissolve: `LS.add_to_track(track, "LS Transition: Dissolve & Dip", { style = 0 })`
- Dip to black: `LS.add_to_track(track, "LS Transition: Dissolve & Dip", { style = 1 })`

- Put this on the track. Overlap two items on that track (a crossfade); the transition lasts as long as the overlap.
- One instance handles every crossfade on the track. Use separate tracks for different transition styles.

### LS Transition: Flash, Glitch & Light Leak

*Placement:* a track.

Put on a track: crossfades cut through a white flash, a digital glitch, a warm light leak or a film burn.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `style` | Style | 0 | 0 to 3 | Flash cuts through white; Glitch cuts with digital breakup; Light leak and Film burn add warm light. Options: 0 Flash, 1 Glitch, 2 Light leak, 3 Film burn. |
| 1 | `strength` | Strength | 0.8 | 0 to 1 | Strength of the flash or light. |
| 2 | `lcr` | Light red | 1 | 0 to 1 | Red part of Light color (0..1). |
| 3 | `lcg` | Light green | 0.62 | 0 to 1 | Green part of Light color (0..1). |
| 4 | `lcb` | Light blue | 0.25 | 0 to 1 | Blue part of Light color (0..1). |
| 5 | `srcmode` | Source | 0 | 0 to 1 | Item crossfades: runs on every crossfade between items on this track. Manual: blends this track into the next track behind it using Manual progress. Options: 0 Item crossfades, 1 Manual (this track to the one behind). |
| 6 | `progress` | Manual progress | 0 | 0 to 1 | Manual mode: 0 shows this track, 1 the track behind. Keyframe 0 to 1 over the transition. |
| 7 | `reverse` | Reverse | 0 | 0 to 1 | Swap outgoing and incoming (use if a direction comes out backwards). 0 off, 1 on. |

Examples:

- White flash: `LS.add_to_track(track, "LS Transition: Flash, Glitch & Light Leak", { style = 0 })`
- Light leak: `LS.add_to_track(track, "LS Transition: Flash, Glitch & Light Leak", { style = 2 })`

- Put this on the track. Overlap two items on that track (a crossfade); the transition lasts as long as the overlap.
- One instance handles every crossfade on the track. Use separate tracks for different transition styles.

### LS Transition: Push & Slide

*Placement:* a track.

Put on a track: crossfades become a push, slide, reveal, split or squeeze in any direction, with optional motion blur.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `style` | Style | 0 | 0 to 4 | Push moves both shots; Slide in covers; Slide out uncovers; Split opens like doors; Squeeze compresses. Options: 0 Push, 1 Slide in, 2 Slide out, 3 Split open, 4 Squeeze. |
| 1 | `dir` | Direction | 0 | 0 to 3 | Direction the pictures move; the new shot enters from the opposite side (Left: it comes in from the right). Options: 0 Left, 1 Right, 2 Up, 3 Down. |
| 2 | `blur` | Motion blur | 0.5 | 0 to 1 | Motion blur during the move. |
| 3 | `ease` | Smoothness | 1 | 0 to 3 | How the transition speeds up and slows down. Options: 0 Linear, 1 Smooth, 2 Ease in, 3 Ease out. |
| 4 | `srcmode` | Source | 0 | 0 to 1 | Item crossfades: runs on every crossfade between items on this track. Manual: blends this track into the next track behind it using Manual progress. Options: 0 Item crossfades, 1 Manual (this track to the one behind). |
| 5 | `progress` | Manual progress | 0 | 0 to 1 | Manual mode: 0 shows this track, 1 the track behind. Keyframe 0 to 1 over the transition. |
| 6 | `reverse` | Reverse | 0 | 0 to 1 | Swap outgoing and incoming (use if a direction comes out backwards). 0 off, 1 on. |

Examples:

- Push left: `LS.add_to_track(track, "LS Transition: Push & Slide", { style = 0, dir = 0 })`
- Slide up: `LS.add_to_track(track, "LS Transition: Push & Slide", { style = 1, dir = 2 })`

- Put this on the track. Overlap two items on that track (a crossfade); the transition lasts as long as the overlap.
- One instance handles every crossfade on the track. Use separate tracks for different transition styles.

### LS Transition: Shape Wipe

*Placement:* a track.

Put on a track: crossfades reveal the next shot through a growing circle, box, diamond, clock sweep, barn doors, angled wipe or blinds, with soft edges and an optional glowing border.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `shape` | Shape | 0 | 0 to 7 | Shape of the reveal. Options: 0 Circle, 1 Box, 2 Diamond, 3 Clock, 4 Barn doors (vertical), 5 Barn doors (horizontal), 6 Angled wipe, 7 Blinds. |
| 1 | `soft` | Softness | 0.08 | 0.002 to 0.5 | Edge softness. |
| 2 | `cx` | Center X | 0 | -1 to 1 | Center, -1 left to 1 right. |
| 3 | `cy` | Center Y | 0 | -1 to 1 | Center, -1 top to 1 bottom. |
| 4 | `angle` | Angle | 0 | -180 to 180 | Angle for Angled wipe and Blinds, degrees. |
| 5 | `count` | Blinds count | 8 | 2 to 40 | Number of blinds. |
| 6 | `border` | Border | 0 | 0 to 0.05 | Glowing edge width (0 = none). |
| 7 | `bcr` | Border red | 1 | 0 to 1 | Red part of Border color (0..1). |
| 8 | `bcg` | Border green | 0.85 | 0 to 1 | Green part of Border color (0..1). |
| 9 | `bcb` | Border blue | 0.5 | 0 to 1 | Blue part of Border color (0..1). |
| 10 | `shrink` | Shrink instead of grow | 0 | 0 to 1 | Shrink from the edges instead of growing from the center. 0 off, 1 on. |
| 11 | `srcmode` | Source | 0 | 0 to 1 | Item crossfades: runs on every crossfade between items on this track. Manual: blends this track into the next track behind it using Manual progress. Options: 0 Item crossfades, 1 Manual (this track to the one behind). |
| 12 | `progress` | Manual progress | 0 | 0 to 1 | Manual mode: 0 shows this track, 1 the track behind. Keyframe 0 to 1 over the transition. |
| 13 | `reverse` | Reverse | 0 | 0 to 1 | Swap outgoing and incoming (use if a direction comes out backwards). 0 off, 1 on. |

Examples:

- Iris open: `LS.add_to_track(track, "LS Transition: Shape Wipe", { shape = 0, soft = 0.05 })`
- Clock wipe: `LS.add_to_track(track, "LS Transition: Shape Wipe", { shape = 3 })`
- Angled wipe with glowing edge: `LS.add_to_track(track, "LS Transition: Shape Wipe", { shape = 6, angle = 30, border = 0.01 })`

- Put this on the track. Overlap two items on that track (a crossfade); the transition lasts as long as the overlap.
- One instance handles every crossfade on the track. Use separate tracks for different transition styles.

### LS Transition: Zoom & Spin

*Placement:* a track.

Put on a track: crossfades punch through with a zoom in, zoom out or spinning zoom, blurred at the peak for speed.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `style` | Style | 0 | 0 to 2 | Zoom in through, zoom out, or spinning zoom. Options: 0 Zoom in, 1 Zoom out, 2 Spin. |
| 1 | `strength` | Strength | 0.6 | 0 to 1 | How far it zooms. |
| 2 | `blur` | Zoom blur | 0.6 | 0 to 1 | Zoom blur at the peak. |
| 3 | `srcmode` | Source | 0 | 0 to 1 | Item crossfades: runs on every crossfade between items on this track. Manual: blends this track into the next track behind it using Manual progress. Options: 0 Item crossfades, 1 Manual (this track to the one behind). |
| 4 | `progress` | Manual progress | 0 | 0 to 1 | Manual mode: 0 shows this track, 1 the track behind. Keyframe 0 to 1 over the transition. |
| 5 | `reverse` | Reverse | 0 | 0 to 1 | Swap outgoing and incoming (use if a direction comes out backwards). 0 off, 1 on. |

Examples:

- Punchy zoom-in: `LS.add_to_track(track, "LS Transition: Zoom & Spin", { style = 0, strength = 0.6 })`

- Put this on the track. Overlap two items on that track (a crossfade); the transition lasts as long as the overlap.
- One instance handles every crossfade on the track. Use separate tracks for different transition styles.

### LS Title: Lower Third

*Placement:* an item (usually a transparent title item; see rule 3).

Name and subtitle bar for the lower part of the screen. Name the item "Name | Subtitle". Drag the item fade-in and fade-out to set how long it animates on and off.

*Text:* Name | Subtitle (item name).

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `style` | Style | 0 | 0 to 3 | Look of the bar. Options: 0 Bar with accent, 1 Pill, 2 Minimal line, 3 Accent block. |
| 1 | `align` | Align | 0 | 0 to 2 | Left, center or right. Options: 0 Left, 1 Center, 2 Right. |
| 2 | `margin` | Side margin | 0.06 | 0 to 0.4 | Distance from the side, fraction of frame width. |
| 3 | `ypos` | Height on screen | 0.8 | 0 to 1 | Vertical center of the bar, fraction of frame height (0.8 is low on screen). |
| 4 | `size` | Text size | 0.05 | 0.015 to 0.15 | Name text height, fraction of frame height. |
| 5 | `subsize` | Subtitle size | 0.6 | 0.3 to 1 | Subtitle size relative to the name. |
| 6 | `brr` | Bar red | 0.07 | 0 to 1 | Red part of Bar (0..1). |
| 7 | `brg` | Bar green | 0.08 | 0 to 1 | Green part of Bar (0..1). |
| 8 | `brb` | Bar blue | 0.1 | 0 to 1 | Blue part of Bar (0..1). |
| 9 | `baropacity` | Bar opacity | 0.85 | 0 to 1 | Bar opacity. |
| 10 | `acr` | Accent red | 0.24 | 0 to 1 | Red part of Accent (0..1). |
| 11 | `acg` | Accent green | 0.87 | 0 to 1 | Green part of Accent (0..1). |
| 12 | `acb` | Accent blue | 0.66 | 0 to 1 | Blue part of Accent (0..1). |
| 13 | `tcr` | Text red | 1 | 0 to 1 | Red part of Text (0..1). |
| 14 | `tcg` | Text green | 1 | 0 to 1 | Green part of Text (0..1). |
| 15 | `tcb` | Text blue | 1 | 0 to 1 | Blue part of Text (0..1). |
| 16 | `font` | Font | 0 | 0 to 6 | Font. Options: 0 Helvetica Neue, 1 Avenir Next, 2 Futura, 3 Georgia, 4 Gill Sans, 5 Menlo, 6 Impact. |
| 17 | `bold` | Bold name | 1 | 0 to 1 | Bold name. 0 off, 1 on. |
| 18 | `anim` | Animation | 0 | 0 to 3 | Animation; plays over the item fade-in and reverses over the fade-out. Options: 0 Slide, 1 Wipe, 2 Fade, 3 Pop. |
| 19 | `animsrc` | Animate with | 0 | 0 to 1 | Item fades or Manual amount. Options: 0 Item fades, 1 Manual. |
| 20 | `amount` | Manual amount | 1 | 0 to 1 | Manual mode: 0 hidden, 1 shown. |

Examples:

- Guest name: `LS.add_title(track, pos, len, "Jane Doe | Drums", "LS Title: Lower Third", { style = 0, align = 0 })` Item name: "Jane Doe | Drums". Item fades 0.5 s.
- Centered pill: `LS.add_title(track, pos, len, "Title | Subtitle", "LS Title: Lower Third", { style = 1, align = 1, font = 1 })`

- Use the panel's + Lower third button, or put it on a transparent title item. The text is the item name; | starts the subtitle.
- If the item's fades already make a crossfade, set Animate with to Manual and keyframe Manual amount.

### LS Title: Scrolling Credits

*Placement:* an item (usually a transparent title item; see rule 3).

Rolling end credits or a sideways news-style crawl. Name the item with lines separated by "|"; a line like "Drums: Larry Seyer" becomes two columns. Set the duration to the item length.

*Text:* Line one | Role: Name | ... (item name).

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `mode` | Mode | 0 | 0 to 1 | Roll up the screen, or crawl sideways along the bottom. Options: 0 Roll up, 1 Crawl left. |
| 1 | `dur` | Duration (s) | 10 | 1 to 600 | Seconds for the whole roll; set it to the item length. |
| 2 | `size` | Text size | 0.045 | 0.015 to 0.15 | Text height, fraction of frame height. |
| 3 | `spacing` | Line spacing | 1.6 | 1 to 3 | Line spacing. |
| 4 | `font` | Font | 1 | 0 to 6 | Font. Options: 0 Helvetica Neue, 1 Avenir Next, 2 Futura, 3 Georgia, 4 Gill Sans, 5 Menlo, 6 Impact. |
| 5 | `tcr` | Text red | 1 | 0 to 1 | Red part of Text (0..1). |
| 6 | `tcg` | Text green | 1 | 0 to 1 | Green part of Text (0..1). |
| 7 | `tcb` | Text blue | 1 | 0 to 1 | Blue part of Text (0..1). |
| 8 | `rcr` | Role red | 0.7 | 0 to 1 | Red part of Role text (0..1). |
| 9 | `rcg` | Role green | 0.7 | 0 to 1 | Green part of Role text (0..1). |
| 10 | `rcb` | Role blue | 0.7 | 0 to 1 | Blue part of Role text (0..1). |
| 11 | `backdrop` | Backdrop | 1 | 0 to 2 | Darkening or color behind the text. Options: 0 None, 1 Dim picture, 2 Solid color. |
| 12 | `bkr` | Backdrop red | 0 | 0 to 1 | Red part of Backdrop color (0..1). |
| 13 | `bkg` | Backdrop green | 0 | 0 to 1 | Green part of Backdrop color (0..1). |
| 14 | `bkb` | Backdrop blue | 0 | 0 to 1 | Blue part of Backdrop color (0..1). |
| 15 | `bkop` | Backdrop opacity | 0.6 | 0 to 1 | Backdrop opacity. |

Examples:

- End credits: `LS.add_title(track, pos, len, "The Larry Seyer Show | Guitar: Larry Seyer | Keys: Larry Seyer | Thanks for watching", "LS Title: Scrolling Credits", { mode = 0, dur = 12 })` Item name: "The Larry Seyer Show | Guitar: Larry Seyer | Keys: Larry Seyer | Thanks for watching".

- Separate lines with |. A line with a colon, like "Drums: Larry", becomes two columns.
- The roll starts with the text just below the frame and ends with it just above. Allow about 1.5 s per line. Item fades have no effect.

### LS Title: Title & Subtitle

*Placement:* an item (usually a transparent title item; see rule 3).

Large centered title with an optional subtitle and backdrop. Name the item "Title | Subtitle". Item fades animate it in and out.

*Text:* Title | Subtitle (item name).

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `ypos` | Height on screen | 0.5 | 0 to 1 | Vertical position, fraction of frame height. |
| 1 | `size` | Title size | 0.1 | 0.02 to 0.3 | Title text height, fraction of frame height. |
| 2 | `subsize` | Subtitle size | 0.4 | 0.15 to 1 | Subtitle size relative to the title. |
| 3 | `tcr` | Title red | 1 | 0 to 1 | Red part of Title color (0..1). |
| 4 | `tcg` | Title green | 1 | 0 to 1 | Green part of Title color (0..1). |
| 5 | `tcb` | Title blue | 1 | 0 to 1 | Blue part of Title color (0..1). |
| 6 | `scr` | Subtitle red | 0.85 | 0 to 1 | Red part of Subtitle color (0..1). |
| 7 | `scg` | Subtitle green | 0.85 | 0 to 1 | Green part of Subtitle color (0..1). |
| 8 | `scb` | Subtitle blue | 0.85 | 0 to 1 | Blue part of Subtitle color (0..1). |
| 9 | `backdrop` | Backdrop | 1 | 0 to 3 | Darkening, color or gradient behind the text. Options: 0 None, 1 Dim picture, 2 Solid color, 3 Bottom gradient. |
| 10 | `bkr` | Backdrop red | 0 | 0 to 1 | Red part of Backdrop color (0..1). |
| 11 | `bkg` | Backdrop green | 0 | 0 to 1 | Green part of Backdrop color (0..1). |
| 12 | `bkb` | Backdrop blue | 0 | 0 to 1 | Blue part of Backdrop color (0..1). |
| 13 | `bkop` | Backdrop opacity | 0.45 | 0 to 1 | Backdrop opacity. |
| 14 | `font` | Font | 1 | 0 to 6 | Font. Options: 0 Helvetica Neue, 1 Avenir Next, 2 Futura, 3 Georgia, 4 Gill Sans, 5 Menlo, 6 Impact. |
| 15 | `bold` | Bold | 1 | 0 to 1 | Bold title. 0 off, 1 on. |
| 16 | `shadow` | Text shadow | 1 | 0 to 1 | Soft text shadow. 0 off, 1 on. |
| 17 | `anim` | Animation | 1 | 0 to 3 | Fade, rise, zoom or typewriter (types the text over the fade-in). Options: 0 Fade, 1 Rise, 2 Zoom, 3 Typewriter. |
| 18 | `animsrc` | Animate with | 0 | 0 to 1 | Item fades or Manual amount. Options: 0 Item fades, 1 Manual. |
| 19 | `amount` | Manual amount | 1 | 0 to 1 | Manual mode: 0 hidden, 1 shown. |

Examples:

- Episode title: `LS.add_title(track, pos, len, "The Spice of Life | The Larry Seyer Show", "LS Title: Title & Subtitle", { anim = 1, font = 1, backdrop = 1 })` Item name: "The Spice of Life | The Larry Seyer Show".
- Typewriter: `LS.add_title(track, pos, len, "Title | Subtitle", "LS Title: Title & Subtitle", { anim = 3, font = 5, backdrop = 0 })`

- Use the panel's + Title button. The text is the item name; | starts the subtitle.
- If the item's fades already make a crossfade, set Animate with to Manual and keyframe Manual amount.

### LS Tutorial: Blur or Pixelate Region

*Placement:* an item or a track.

Hides part of the picture, such as an email address, serial number or face, with blur, pixelation or a solid box. Stack several to hide several things.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `rx` | Area left | 0.4 | 0 to 1 | Hidden area, fractions of the frame (left, top, width, height). |
| 1 | `ry` | Area top | 0.4 | 0 to 1 | Area top. |
| 2 | `rw` | Area width | 0.2 | 0.005 to 1 | Area width. |
| 3 | `rh` | Area height | 0.1 | 0.005 to 1 | Area height. |
| 4 | `mode` | Mode | 0 | 0 to 2 | Blur, pixelate or a solid box. Options: 0 Blur, 1 Pixelate, 2 Solid box. |
| 5 | `strength` | Strength | 0.6 | 0 to 1 | Blur or pixel size; 0.6 or more makes text unreadable. |
| 6 | `shape` | Shape | 1 | 0 to 2 | Rectangle, rounded or ellipse. Use Rectangle for areas that touch the frame edges. Options: 0 Rectangle, 1 Rounded, 2 Ellipse. |
| 7 | `feather` | Edge softness | 0.004 | 0 to 0.1 | Edge softness, fraction of frame height. |
| 8 | `bcr` | Box red | 0.1 | 0 to 1 | Red part of Box color (0..1). |
| 9 | `bcg` | Box green | 0.1 | 0 to 1 | Green part of Box color (0..1). |
| 10 | `bcb` | Box blue | 0.1 | 0 to 1 | Blue part of Box color (0..1). |

Examples:

- Hide an email address: `LS.add_to_item(item, "LS Tutorial: Blur or Pixelate Region", { rx = 0.6, ry = 0.05, rw = 0.3, rh = 0.05, mode = 0, strength = 0.8 })`

- Stack several instances to hide several things.

### LS Tutorial: Callout

*Placement:* an item (usually a transparent title item; see rule 3).

Labels a control in a screen recording: an outlined highlight box, an arrow and a label pill, in the style of the Larry Seyer Drums tutorials. The label text is the item name. Item fades animate it in and out.

*Text:* Label text (item name).

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `bx` | Box left | 0.08 | 0 to 1 | Highlight box rectangle, fractions of the frame (left, top, width, height). |
| 1 | `by` | Box top | 0.1 | 0 to 1 | Box top. |
| 2 | `bw` | Box width | 0.18 | 0.005 to 1 | Box width. |
| 3 | `bh` | Box height | 0.05 | 0.005 to 1 | Box height. |
| 4 | `lx` | Label X | 0.45 | 0 to 1 | Label pill center X, fraction of frame width. |
| 5 | `ly` | Label Y | 0.125 | 0 to 1 | Label pill center Y, fraction of frame height. |
| 6 | `style` | Style | 0 | 0 to 4 | Which parts to draw. Numbered badge is a pill sized for a short number. Options: 0 Box + arrow + label, 1 Arrow + label, 2 Label only, 3 Box only, 4 Numbered badge. |
| 7 | `size` | Text size | 0.032 | 0.01 to 0.12 | Label text height, fraction of frame height. |
| 8 | `thick` | Line width | 0.0028 | 0.0005 to 0.01 | Line width of the box, arrow and pill outline, fraction of frame height. |
| 9 | `radius` | Box rounding | 0.25 | 0 to 1 | Box corner rounding (0 square to 1 fully round). |
| 10 | `acr` | Accent red | 0.24 | 0 to 1 | Red part of Accent (0..1). |
| 11 | `acg` | Accent green | 0.87 | 0 to 1 | Green part of Accent (0..1). |
| 12 | `acb` | Accent blue | 0.66 | 0 to 1 | Blue part of Accent (0..1). |
| 13 | `fcr` | Label fill red | 0.06 | 0 to 1 | Red part of Label fill (0..1). |
| 14 | `fcg` | Label fill green | 0.09 | 0 to 1 | Green part of Label fill (0..1). |
| 15 | `fcb` | Label fill blue | 0.09 | 0 to 1 | Blue part of Label fill (0..1). |
| 16 | `tcr` | Text red | 1 | 0 to 1 | Red part of Text (0..1). |
| 17 | `tcg` | Text green | 1 | 0 to 1 | Green part of Text (0..1). |
| 18 | `tcb` | Text blue | 1 | 0 to 1 | Blue part of Text (0..1). |
| 19 | `dim` | Dim outside box | 0 | 0 to 1 | Darkens everything outside the box. |
| 20 | `font` | Font | 0 | 0 to 6 | Font. Options: 0 Helvetica Neue, 1 Avenir Next, 2 Futura, 3 Georgia, 4 Gill Sans, 5 Menlo, 6 Impact. |
| 21 | `anim` | Animation | 2 | 0 to 3 | Fade, Draw on (the arrow grows toward the target) or Pop. Options: 0 None, 1 Fade, 2 Draw on, 3 Pop. |
| 22 | `animsrc` | Animate with | 0 | 0 to 1 | Item fades or Manual amount. Options: 0 Item fades, 1 Manual. |
| 23 | `amount` | Manual amount | 1 | 0 to 1 | Manual mode: 0 hidden, 1 shown. |

Examples:

- Point at a control: `LS.add_title(track, pos, len, "Call Outs", "LS Tutorial: Callout", { bx = 0.08, by = 0.1, bw = 0.18, bh = 0.05, lx = 0.45, ly = 0.125 })` Item name: "Call Outs". Place the box over the control and the label beside it.

- Use the panel's + Callout button. The label text is the item name.
- The default colors match the Larry Seyer Drums tutorials (mint outline, dark pill).
- If the item's fades already make a crossfade, set Animate with to Manual and keyframe Manual amount.
- The arrow runs from the label toward the box from any direction, so the label can sit on any side.

### LS Tutorial: Magnifier

*Placement:* an item or a track.

A zoom lens that shows a small detail enlarged somewhere else on screen, with a marker on the original spot and an optional connecting line. Item fades animate it.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `dx` | Detail X | 0.3 | 0 to 1 | Spot to magnify X, fraction of frame width. |
| 1 | `dy` | Detail Y | 0.3 | 0 to 1 | Spot to magnify Y, fraction of frame height. |
| 2 | `lx` | Lens X | 0.7 | 0 to 1 | Where the lens appears X. |
| 3 | `ly` | Lens Y | 0.5 | 0 to 1 | Where the lens appears Y. |
| 4 | `size` | Lens size | 0.35 | 0.05 to 1 | Lens diameter, fraction of frame height. |
| 5 | `zoom` | Zoom | 2.5 | 1 to 8 | Magnification. |
| 6 | `shape` | Shape | 0 | 0 to 1 | Circle or rounded square. Options: 0 Circle, 1 Rounded square. |
| 7 | `border` | Border width | 0.004 | 0 to 0.03 | Border width, fraction of frame height. |
| 8 | `bcr` | Border red | 1 | 0 to 1 | Red part of Border color (0..1). |
| 9 | `bcg` | Border green | 1 | 0 to 1 | Green part of Border color (0..1). |
| 10 | `bcb` | Border blue | 1 | 0 to 1 | Blue part of Border color (0..1). |
| 11 | `shadow` | Shadow | 0.5 | 0 to 1 | Lens shadow. |
| 12 | `marker` | Mark the detail | 1 | 0 to 1 | Circles the original spot and draws a line to the lens. 0 off, 1 on. |
| 13 | `animsrc` | Animate with | 0 | 0 to 1 | Item fades or Manual amount. Options: 0 Item fades, 1 Manual. |
| 14 | `amount` | Manual amount | 1 | 0 to 1 | Manual mode: 0 hidden, 1 shown. |

Examples:

- Enlarge a small knob: `LS.add_to_item(item, "LS Tutorial: Magnifier", { dx = 0.3, dy = 0.4, lx = 0.7, ly = 0.5, size = 0.35, zoom = 3 })`

- If the item's fades already make a crossfade, set Animate with to Manual and keyframe Manual amount.

### LS Tutorial: Spotlight

*Placement:* an item or a track.

Dims and optionally blurs everything except one area, with an outline around it, to pull attention to a control or part of the screen. Item fades animate it.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `sx` | Area left | 0.3 | 0 to 1 | Spotlight area, fractions of the frame (left, top, width, height). |
| 1 | `sy` | Area top | 0.3 | 0 to 1 | Area top. |
| 2 | `sw2` | Area width | 0.4 | 0.01 to 1 | Area width. |
| 3 | `sh2` | Area height | 0.3 | 0.01 to 1 | Area height. |
| 4 | `shape` | Shape | 1 | 0 to 2 | Rectangle, rounded or ellipse. Options: 0 Rectangle, 1 Rounded, 2 Ellipse. |
| 5 | `radius` | Rounding | 0.15 | 0 to 1 | Rounding for the Rounded shape. |
| 6 | `feather` | Edge softness | 0.01 | 0 to 0.2 | Edge softness, fraction of frame height. |
| 7 | `dim` | Dim outside | 0.6 | 0 to 1 | Darkness outside the area. |
| 8 | `blur` | Blur outside | 0 | 0 to 1 | Blur outside the area (slower at 4K). |
| 9 | `outline` | Outline width | 0.003 | 0 to 0.02 | Outline width, fraction of frame height (0 = none). |
| 10 | `ocr` | Outline red | 0.24 | 0 to 1 | Red part of Outline color (0..1). |
| 11 | `ocg` | Outline green | 0.87 | 0 to 1 | Green part of Outline color (0..1). |
| 12 | `ocb` | Outline blue | 0.66 | 0 to 1 | Blue part of Outline color (0..1). |
| 13 | `animsrc` | Animate with | 0 | 0 to 1 | Item fades or Manual amount. Options: 0 Item fades, 1 Manual. |
| 14 | `amount` | Manual amount | 1 | 0 to 1 | Manual mode: 0 off, 1 full. |

Examples:

- Focus on one panel: `LS.add_to_item(item, "LS Tutorial: Spotlight", { sx = 0.1, sy = 0.15, sw2 = 0.35, sh2 = 0.4, shape = 1, dim = 0.6 })`

- If the item's fades already make a crossfade, set Animate with to Manual and keyframe Manual amount.

### LS Compose: Blend Modes

*Placement:* an item or a track.

Blends this layer over the tracks behind it like a photo editor layer: multiply, screen, overlay, soft light, add, subtract, difference, lighten, darken and color dodge.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `mode` | Blend mode | 2 | 0 to 10 | How this layer combines with the tracks behind it. Options: 0 Normal, 1 Multiply, 2 Screen, 3 Overlay, 4 Soft light, 5 Add, 6 Subtract, 7 Difference, 8 Lighten, 9 Darken, 10 Color dodge. |
| 1 | `opacity` | Opacity | 1 | 0 to 1 | Layer opacity. |

Examples:

- Light leak overlay: `LS.add_to_item(item, "LS Compose: Blend Modes", { mode = 2, opacity = 0.8 })` Put on a track holding a light-leak clip, above the footage.

- Put this on the track in front; it blends that track's video over everything behind it.

### LS Compose: Green Screen Key

*Placement:* an item or a track.

Removes a green or blue backdrop (or any picked color) and puts this clip over the tracks behind it, with spill suppression, edge control and a garbage matte crop.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `keycolor` | Key color | 0 | 0 to 2 | Backdrop color to remove. Options: 0 Green, 1 Blue, 2 Custom hue. |
| 1 | `keyhue` | Custom hue | 120 | 0 to 360 | Custom hue in degrees (used with Custom hue). |
| 2 | `tolerance` | Tolerance | 0.12 | 0 to 1 | Raise if backdrop color remains; lower if the subject gets holes. |
| 3 | `softness` | Softness | 0.12 | 0.005 to 1 | Edge softness of the key. |
| 4 | `choke` | Edge choke | 1 | 0.25 to 4 | Above 1 tightens edges. |
| 5 | `spill` | Spill removal | 0.7 | 0 to 1 | Removes backdrop color reflected on the subject. |
| 6 | `cropl` | Crop left | 0 | 0 to 0.5 | Garbage matte: crop away parts outside the backdrop. |
| 7 | `cropr` | Crop right | 0 | 0 to 0.5 | Crop right. |
| 8 | `cropt` | Crop top | 0 | 0 to 0.5 | Crop top. |
| 9 | `cropb` | Crop bottom | 0 | 0 to 0.5 | Crop bottom. |
| 10 | `showmatte` | Show matte | 0 | 0 to 1 | Shows the key as black and white. Turn off before rendering. 0 off, 1 on. |

Examples:

- Standard green screen: `LS.add_to_item(item, "LS Compose: Green Screen Key", { keycolor = 0 })` Put on the green-screen clip on a track in front of the new background.

### LS Compose: Split Screen

*Placement:* a track.

Arranges this track and the tracks behind it side by side, stacked, one large with two small, a 2x2 grid or three columns, with gaps, rounded corners and per-panel framing.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `layout` | Layout | 0 | 0 to 4 | Panel arrangement. Options: 0 Side by side, 1 Stacked, 2 One large + two small, 3 2x2 grid, 4 Three columns. |
| 1 | `split` | Split position | 0.5 | 0.2 to 0.8 | Where two-panel layouts divide. |
| 2 | `gap` | Gap | 0.008 | 0 to 0.05 | Gap between panels, fraction of frame height. |
| 3 | `margin` | Outer margin | 0 | 0 to 0.1 | Outer margin, fraction of frame height. |
| 4 | `radius` | Corner radius | 0 | 0 to 0.2 | Panel corner rounding. |
| 5 | `gcr` | Gap red | 0.05 | 0 to 1 | Red part of Gap color (0..1). |
| 6 | `gcg` | Gap green | 0.05 | 0 to 1 | Green part of Gap color (0..1). |
| 7 | `gcb` | Gap blue | 0.06 | 0 to 1 | Blue part of Gap color (0..1). |
| 8 | `pan1` | Panel 1 pan | 0 | -1 to 1 | Which part of the source shows in its panel, -1..1 (along the cropped direction). |
| 9 | `pan2` | Panel 2 pan | 0 | -1 to 1 | Panel 2 pan. |
| 10 | `pan3` | Panel 3 pan | 0 | -1 to 1 | Panel 3 pan. |
| 11 | `pan4` | Panel 4 pan | 0 | -1 to 1 | Panel 4 pan. |
| 12 | `zoomall` | Zoom | 1 | 1 to 3 | Zoom inside every panel. |

Examples:

- Two cameras side by side: `LS.add_to_track(track, "LS Compose: Split Screen", { layout = 0, gap = 0.008 })` Put on the front video track; the track directly behind it supplies panel 2.

- Panel 1 is this track; panels 2-4 are the next tracks behind it that have video.

### LS Time: Freeze & Stutter

*Placement:* an item or a track.

Freeze holds the picture from the moment it switches on (automate it for freeze frames). Stutter holds every frame for several frames for a choppy, stop-motion feel.

| API index | var | Control | Default | Range | Meaning |
|---|---|---|---|---|---|
| 0 | `freeze` | Freeze | 0 | 0 to 1 | Turn on (keyframe it) to hold the current picture. 0 off, 1 on. |
| 1 | `stutter` | Stutter (hold frames) | 1 | 1 to 30 | Holds each frame for this many frames (1 = off). |

Examples:

- Freeze frame: `LS.add_to_item(item, "LS Time: Freeze & Stutter", { freeze = 1 })` Keyframe Freeze from 0 to 1 at the moment to hold, and back to 0 to release.
