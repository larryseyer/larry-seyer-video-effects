# Larry Seyer Video Effects manual

Version {{VERSION}} - {{COUNT}} video effects for REAPER.

Larry Seyer Video Effects turns REAPER's Video Processor into a complete set of video effects: color grading with
lift, gamma and gain wheels, titles and lower thirds, tutorial callouts and zooms, transitions,
picture-in-picture, borders and shadows, looks, and a multicam switcher for cutting between cameras.
Every effect is an ordinary Video Processor preset, so projects render the same on any computer that has
the presets, with or without the control panel open.

## Installing

1. Install [ReaPack](https://reapack.com) if you do not have it.
2. *Extensions > ReaPack > Import repositories*, paste
   `{{INDEX_URL}}`
3. *Extensions > ReaPack > Browse packages*, type **Larry Seyer** in the filter, right-click
   **Larry Seyer Video Effects** and choose *Install*. Also install **ReaImGui** (type *ReaImGui* in the same
   window) if you do not have it; the panel and the Multicam window need it. Click *Apply*, and restart REAPER if
   ReaPack asks you to. Importing the repository in step 2 does not install anything by itself.
4. **Important - run it once after installing:** ReaPack copies the files but cannot add presets by itself. Open
   *Actions > Show action list*, search **Larry Seyer Video Effects** and run it. The panel opens and adds the
   {{COUNT}} **LS** presets to the Video Processor preset list. Until you do this, the presets are not there. If
   ReaImGui is missing, it offers to open ReaPack on it.

Updates arrive through *ReaPack > Synchronize packages*; the panel and the Multicam window bring the presets up to
date the next time they open.

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
  selection) carrying that effect, and select it. The item name is the text; `|` starts a new line. The item's
  fade-in and fade-out handles set how long it animates on and off. The item goes on the first track named
  **Titles** that has nothing at that time; only when every Titles track is busy there is a new one added, in
  front of everything (a track shows one item at a time).
- **Lock** keeps the panel on the current item or track while you select other things. While it is on, the line
  under the buttons reads *Locked to ...* in color.
- Effects that work on a whole track (transitions, Split Screen) go on the selected item's track; the panel then
  shows that track and says so.

Without the panel: add a Video processor to an item or track and choose any **LS ...** entry from its preset list.

## Multicam

Cut a shoot with several cameras the way a live switcher does: play it and press the number of the camera you
want, or click that camera in the Video window.

1. Put each camera on its own track.
2. Click **Multicam** in the panel (or run *Larry Seyer Video Effects - Multicam* from the Actions list). Select
   the camera tracks (2 to 9; top to bottom become cameras 1, 2, 3...) and click **Set up from selected tracks**.
   A *Multicam* track with the **Multicam Switcher** goes in front of them, and each camera track gets a
   **Multicam Camera** effect with its number. With **Line them up by their audio** ticked (the default), every
   camera's clips then move to where their sound matches camera 1's (see *Lining cameras up by audio* below).
3. While the Multicam window is open, the Video window shows **switcher view**: the program large, every camera
   underneath with its track name, and the camera on air outlined in red.
4. Play. Press **1-9**, click a camera button in the window, or click a camera in the Video window. Each switch is
   a cut at that moment. Playing a section again and switching replaces its earlier cuts from your first switch
   to your last, and any cut in the half second before your first switch. **Space** plays and stops.
5. Stopped, a number (or a click) changes the camera of the shot at the edit cursor. **Left/Right arrows** jump
   between cuts, **Delete** removes the cut at the cursor.
6. **Switch with** sets how switches happen: **Cut**, or a **Transition** (cross dissolve, dip to black or white,
   additive, blur or luma dissolve, push, slide in or out, split open, squeeze) with its length in frames. Hold
   **Shift** for the other one on a single switch. *Give it the transition* and *Make it a cut* change the cut at
   the cursor.
7. Close the window: the Video window goes back to the program, which is what renders.

The cuts are points on the Multicam Switcher's **Camera** envelope, so you can also drag, copy or delete them in
the arrange view. Each point carries its cut's transition in its value, just above the camera number (2.0288 is
camera 2 with a 15-frame cross dissolve), so the transition always moves with the cut. Change a cut's camera or
transition in the Multicam window; a whole number typed into a point makes it use the switcher's Transition
controls. Projects cut before version 1.1.7, which kept transitions on separate envelopes, are converted when the
Multicam window opens; check the transitions of a converted project, since some can come back as straight cuts. Transitions play and render in order; jumping the play cursor into one shows a straight cut.

- **Number keys anywhere in REAPER:** the keys work while the Multicam window has focus. After clicking in the
  Video window, focus is there; to switch from the keyboard then, assign *Larry Seyer Video Effects - Multicam
  camera 1* to *9* to the number keys (*Actions > Show action list*, select one, *Add* a shortcut), and the
  *(Shift)* versions to Shift+number.
- **Color matching:** put color effects on a camera track before its Multicam Camera effect; that effect must
  stay last (the Multicam window moves it back when it opens).
- **Portrait clips** (a phone held upright) show with black bars at the sides, as REAPER shows them on their own.
- **A camera that starts late or stops early** shows black (and *no video* in switcher view) where its track has
  no video.
- **One multiview recording** (four or nine cameras in one picture): put it on the track behind the switcher and
  set the switcher's *Source* to *2x2 multiview* or *3x3 multiview*. **Multiview Camera Select** is the per-item
  alternative.
- Camera audio plays as usual; mute or lower the camera tracks if your mix is on other tracks.

### Lining cameras up by audio

Cameras are rarely started at the same moment. If each one recorded the sound of the performance (its own
microphone, or a feed from the desk), the Multicam window lines them up for you: open **Line up by audio**, choose
the **reference** (camera 1 by default, or any other track with clips, such as a board mix) and click **Line up
the cameras**. Every clip on every camera track moves to where its sound matches the reference, to within a
millisecond; the window lists what moved. **Undo** puts everything back in one step.

![The Multicam window after lining up four cameras by their audio](images/multicam_window.jpg)

- A camera stopped and started again (several clips on its track) is fine: each clip is lined up on its own.
- A clip that belongs before the start of the project is trimmed at its start instead.
- Clips whose sound does not match (a silent camera, a different song) stay where they are, and the list says so.
  A clip needs about five seconds of sound in common with the reference.
- Cameras' clocks run at slightly different speeds. When a clip drifts more than 10 ms against the reference
  over its length, it is lined up at its middle and the list says how far it drifts.
- The sync uses each clip's audio as it is on the timeline; it does not change the video or the sound.

## Things that work the same everywhere

- **Layers:** *Project Settings > Video > Track order* decides whether the top or the bottom track is in front.
  Effects that place or frame a picture draw the tracks behind them as the background, so put the foreground clip
  on a track in front of it. The panel's **+** buttons put new title tracks on the correct side for either setting.
- **Transitions:** put a transition effect on a track; every crossfade between items on that track becomes the
  transition, as long as the crossfade.
- **Animated entrances** follow the item fades (titles, callouts, picture-in-picture, Zoom to Region,
  Spotlight, Magnifier). Where the edit cursor is inside a fade, the effect shows part way in; set *Animate with*
  to *Manual* to keep it fully on regardless of the fades.
- **Still pictures:** REAPER treats a picture (PNG, JPG) as a 5-second clip: with *Loop source* off it disappears
  after 5 s, and with it on, effects that move over time start again every 5 s. When you add an effect to a
  picture item, the panel makes the picture hold for the whole item (it wraps the file in a long section of
  itself), so Pan & Zoom and Scrolling Credits run once from start to end. Title items from the **+** buttons are
  made that way.
- **Vertical and square projects:** REAPER fits a clip of a different shape inside the frame with bars (a wide
  clip in a 1080x1920 project shows as a band across the middle). Add **Reframe** to the clip to fill the frame
  and choose which part shows.
- **Fonts:** the Font menus name styles (Clean sans, Serif, Mono...). Each style uses a font that comes with
  macOS, Windows or Linux, picked when the panel installs the presets on that computer.
- **Switching controls during playback:** REAPER prepares video frames ahead of the play position, so a control
  changed while playing (for example ticking Freeze) shows up about a second later. Keyframes take effect on
  their exact frame.
- **Speed:** most effects are light. Effects that process every pixel (Color Grade with hue rotate or vibrance,
  Hue Curves, Isolate Color, Looks, Sharpen, Green Screen, Blend Modes, some transitions) are slower at 4K.
  For smooth playback while editing, lower the preview resolution in the Video window, or bypass them until
  the final render.

## Using Larry Seyer Video Effects with AI

`docs/AI-REFERENCE.md` is a complete reference written for AI agents, with a scripting API (`lib/agent.lua`)
that takes control names instead of numbers. For Claude Code, copy `ai/claude-skill/larry-seyer-video-effects` into
`~/.claude/skills/`; Claude then knows how to use every effect when asked to build or edit a video in REAPER.

## The effects
