# Troubleshooting

## Play Uses Old Script Text

The editor flushes the active text buffer before Play and Export. If a diagnostic still points at old code, stop preview and play again.

## Web Export Fails

The web exporter refuses non-empty destination folders. Choose a new folder or empty the destination yourself before exporting.

## Wren Errors

Preview output lines like `[wren:compile] main:12: ...` are mirrored into editor diagnostics. Click the diagnostic to open the script.

## Missing Assets

Sprite texture paths are resolved relative to `assets/`. The editor reports missing sprite assets as errors and unused image assets as warnings.

## Broken Dialogue Or Combat Actions

Use the structured action pickers when possible. Dialogue actions validate declared dialogue ids and node labels. Combat actions are disabled until the project has a combat database with at least one encounter.

## New Project Feels Empty

Use the starter templates on the Projects screen. The default starter includes a player, camera follow, NPC dialogue, and an ending marker so Play works immediately.
