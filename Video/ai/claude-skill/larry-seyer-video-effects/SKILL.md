---
name: larry-seyer-video-effects
description: Use when building or editing a video in REAPER with the Larry Seyer Video Effects pack - titles, lower thirds, callouts, zoom to region, spotlight, transitions, color grading, picture-in-picture, logos, borders and shadows, looks, or multicam from a multiview recording - including Larry Seyer Drums (LSD) and Sparks of Light (SOL) tutorial videos.
---

# Larry Seyer Video Effects

Larry Seyer Video Effects (version 1.0.1) is a set of 40 REAPER Video Processor effects. Read `reference.md` in this
folder before adding or changing effects: it has every effect's preset name, placement, controls with API
index, ranges and meaning, and working examples.

## How to work

1. Drive REAPER with ReaScript Lua (or a REAPER MCP server). Load the scripting API:
   `local LS = dofile(reaper.GetExtState("LS_VIDEO_FX", "path") .. "lib/agent.lua")` then `LS.ensure_presets()`.
   If that ExtState is empty, ask the user to run *Larry Seyer Video Effects* once from REAPER's Actions list.
2. Pick effects from `reference.md` section 6. Use `LS.add_to_item`, `LS.add_to_track`, `LS.add_title`,
   `LS.set` and `LS.keyframe` with control names and real values in range.
3. Follow the rules in `reference.md` section 4. The ones mistakes usually come from:
   - titles, lower thirds, callouts and credits get their text from the **item name** (`|` = new line) and belong on
     a transparent title item (`LS.add_title`);
   - **item fades** time the in/out animation;
   - **transitions go on the track** and run on overlapping items;
   - the foreground goes on the **upper** track;
   - values are real values, never 0..1 normalized.
4. Before finishing, turn off preview-only switches (`split`, `showmask`, `showbox`, `showmatte`) and check the
   result: render a short section or ask the user to look at REAPER's Video window.

## Tutorial videos (LSD, SOL)

Section 5 of `reference.md` has ready recipes: opening title, presenter lower third, callouts pointing at app
controls, zooming into a screen recording, dissolves between screenshots, a corner logo, blurring private
details and end credits. Keep the house style: callouts and lower thirds use the default mint accent
(0.24, 0.87, 0.66) with dark fills unless the user asks otherwise.
