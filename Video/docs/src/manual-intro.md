# Larry Seyer Video Effects manual

Version {{VERSION}} - {{COUNT}} video effects for REAPER.

Larry Seyer Video Effects turns REAPER's Video Processor into a complete set of video effects: color grading with
DaVinci Resolve-style wheels, titles and lower thirds, tutorial callouts and zooms, transitions,
picture-in-picture, borders and shadows, looks, and multicam editing from a multiview recording.
Every effect is an ordinary Video Processor preset, so projects render the same on any computer that has
the presets, with or without the control panel open.

## Installing

1. Install [ReaPack](https://reapack.com) and [ReaImGui](https://github.com/cfillion/reaimgui) if you do not
   have them (ReaImGui is in ReaPack's default repository: *Extensions > ReaPack > Browse packages*, search
   "ReaImGui").
2. *Extensions > ReaPack > Import repositories*, paste
   `{{INDEX_URL}}`
3. *Extensions > ReaPack > Browse packages*, type **Larry Seyer** in the filter, right-click
   **Larry Seyer Video Effects**, choose *Install*, then click *Apply*. Importing the repository in step 2 does not
   install anything by itself.
4. **Important - run it once after installing:** ReaPack copies the files but cannot add presets by itself. Open *Actions > Show action list*, search **Larry Seyer Video Effects** and run it. The panel opens and adds the 40 **LS** presets to the Video Processor preset list. Until you do this, the presets are not there.

Updates arrive through *ReaPack > Synchronize packages*.

## Using the panel

- Select an **item** to put effects on that clip, or a **track** for everything on the track.
- Click an effect in the library on the left; its controls appear on the right. Hover any control for an
  explanation, double-click it to reset.
- **Keyframes:** the diamond beside a control adds a keyframe at the edit cursor (click again to remove).
  Once a control has keyframes, changing it keys the new value at the edit cursor. *< Key* and *Key >* jump
  between keyframes, *Keyframe all* keys every control. Keyframes are normal REAPER envelopes.
- **Frame pad:** effects with positions or areas show a frame you drag on (points move, areas move and resize
  from the corner square). Watch the result in REAPER's Video window.
- **+ Lower third, + Title, + Callout** add a transparent title item at the edit cursor (or over the time
  selection) carrying that effect. The item name is the text; `|` starts a new line. The item's fade-in and
  fade-out handles set how long it animates on and off.
- **Lock** keeps the panel on the current item or track while you select other things.

Without the panel: add a Video processor to an item or track and choose any **LS ...** entry from its preset list.

## Things that work the same everywhere

- **Layers:** video tracks higher in the track list are in front. Effects that place or frame a picture draw
  the tracks below as the background, so put the foreground clip on the upper track.
- **Transitions:** put a transition effect on a track; every crossfade between items on that track becomes the
  transition, as long as the crossfade.
- **Animated entrances** follow the item fades (titles, callouts, picture-in-picture, Zoom to Region,
  Spotlight, Magnifier).
- **Speed:** most effects are light. Effects that process every pixel (Color Grade with hue rotate or vibrance,
  Hue Curves, Isolate Color, Looks, Sharpen, Green Screen, Blend Modes, some transitions) are slower at 4K.
  For smooth playback while editing, lower the preview resolution in the Video window, or bypass them until
  the final render.

## Using Larry Seyer Video Effects with AI

`docs/AI-REFERENCE.md` is a complete reference written for AI agents, with a scripting API (`lib/agent.lua`)
that takes control names instead of numbers. For Claude Code, copy `ai/claude-skill/larry-seyer-video-effects` into
`~/.claude/skills/`; Claude then knows how to use every effect when asked to build or edit a video in REAPER.

## The effects
