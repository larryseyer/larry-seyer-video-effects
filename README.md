# Larry Seyer Video Effects for Reaper

Video effects for REAPER's Video Processor with a control panel: color grading, titles, tutorial callouts and
zooms, transitions, picture-in-picture, borders and shadows, looks, and a multicam switcher. 43 effects,
installable with [ReaPack](https://reapack.com). REAPER itself is made by Cockos and is not part of this
repository.

## Install

1. Install [ReaPack](https://reapack.com) if you do not have it.
2. *Extensions > ReaPack > Import repositories*, paste:

   ```
   https://raw.githubusercontent.com/larryseyer/larry-seyer-video-effects/main/index.xml
   ```

3. *Extensions > ReaPack > Browse packages*, type **Larry Seyer**, right-click **Larry Seyer Video Effects**,
   *Install*. Also install **ReaImGui** (type *ReaImGui* in the same window) if you do not have it. Click *Apply*,
   and restart REAPER if ReaPack asks you to.
4. Run **Larry Seyer Video Effects** once from *Actions > Show action list*. The control panel opens and adds the
   presets to the Video Processor (ReaPack cannot do that part). If ReaImGui is missing, it offers to open
   ReaPack on it.

Updates arrive with *Extensions > ReaPack > Synchronize packages*; the panel and the Multicam window bring the
presets up to date the next time they open.

## Multicam

*Larry Seyer Video Effects - Multicam* (also the **Multicam** button in the panel) sets up a switcher in front of
your camera tracks, lines the cameras up by their sound, and lets you cut between them while the project plays.

The effects, panel and manual are in [Video](Video) ([Manual](Video/docs/MANUAL.md)).

## License

MIT - see [LICENSE](LICENSE).
