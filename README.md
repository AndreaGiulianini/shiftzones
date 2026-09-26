# ShiftZones

Window zones for macOS, in the style of PowerToys **FancyZones**: define zones for each display, drag a window
while holding **⇧ Shift** and drop it on a zone — the window takes the zone's position and size. No keyboard
shortcuts to learn.

## Features

- **Per-display zones**: every display has its own layout, recognized across reboots and arrangement changes.
- **Hand-editable text file** (`~/.config/shiftzones/zones.conf`): zones as % of the screen, applied as soon as
  you save. The file is rewritten when a display is connected or disconnected, keeping your zones.
- **Drag + key**: hold the activation key (⇧ Shift by default) while dragging a window. The zones appear below
  the window; on release the window snaps to the highlighted one. Releasing the key before the mouse cancels
  the snap.
- **Combine zones**: also hold **⌃ Control** and move across several zones to merge them into a single area.
- **Size restore**: a snapped window goes back to its previous size when you drag it away.
- **Full-screen visual editor** on the chosen display:
  - starting templates: Columns, Rows, Grid, Priority (large center zone, great for ultrawides);
  - drag zones to move them and their edges to resize them, snapping to the other zones' edges;
  - shared edges move together, like grid dividers (hold ⌥ to move only the zone's own edge);
  - right-click to split into columns or rows, duplicate, delete; double-click empty space to add a zone;
  - ⌘Z undo, ↩ save, esc exit without saving.
- **Adjustable spacing** between zones and from the screen edges.
- **Default layouts** based on aspect ratio: 3-zone Priority on ultrawides, 2 columns on regular displays,
  2 rows on portrait ones.

## Requirements

- macOS 13 or later
- Swift 5.10+ (the Command Line Tools are enough: `xcode-select --install`)

## Building

```bash
./scripts/build.sh        # creates build/ShiftZones.app
./scripts/run.sh          # rebuilds, quits the running instance and reopens the app
swift run CoreChecks      # checks for the logic (templates, geometry, editor, zones file)
```

To install it, move `build/ShiftZones.app` to `/Applications`.

### Accessibility permission

ShiftZones moves other apps' windows through the Accessibility API, so on first launch it asks for permission
in **System Settings › Privacy & Security › Accessibility**. The app activates by itself as soon as the
permission is granted.

With the default ad-hoc signature, macOS treats every new build as a different app: after a rebuild ShiftZones
is still checked in the list but doesn't work. In that case remove it with **−** and add it again. To stop
having to do that, create a local signing certificate once (it asks for your Mac password):

```bash
./scripts/create-signing-cert.sh
```

From then on `build.sh` always signs with the same certificate and the permission survives rebuilds.

## Usage

The menu bar icon lets you turn zones on and off, open the editor for each display and the settings:

| Setting | Default |
| --- | --- |
| Key to use zones (or "none" to keep them always active) | ⇧ Shift |
| Key to combine zones | ⌃ Control |
| Spacing between zones | 8 pt |
| Show zones on all displays | yes |
| Restore the original size outside a zone | yes |
| Open at login | no |

### Zones file

Zones live in `~/.config/shiftzones/zones.conf` (menu › *Open Zones File*; holding ⌥ turns the item into
*Show Zones File in Finder*). Each display has a section with its id and one line per zone:

```
[ZQE-CBA · 3440 × 1440 · primary]
id = 7D8D3FC7-5ADC-4AA2-84C5-73B58E04C845
#     x      y  width height
      0      0     30    100
     30      0     40    100
     70      0     30     50
     70     50     30     50
```

- Values are **percentages of the usable screen area** (menu bar and Dock excluded), origin at the top-left.
  Decimals (`33.3` or `33,3`) and a `%` sign are allowed; anything after `#` is a comment.
- The number shown on each zone is the position of its line. A display with no lines has no zones.
- Changes apply **as soon as you save**. If the file has an error, the menu and the settings show the line
  and the reason, and the last valid zones stay active.
- When **a display is connected or disconnected** the file is rewritten from scratch: connected displays are
  listed left to right with their zones (new ones with default zones), disconnected ones move to the bottom
  and get their zones back when reconnected. Hand-written comments are lost.
- If the file had errors when it was rewritten, your version is saved as `zones.conf.bak`.
- The visual editor saves to this file too.

### Living with macOS window tiling

Since macOS 15 the system has its own window tiling:

- **⌥ while dragging** shows the native tiling zones: that's why ShiftZones doesn't use ⌥ as a default key.
- **Dragging to the screen edges** tiles the window. If both features fight over the window when you release
  it near an edge, turn off *Drag windows to screen edges to tile* in
  **System Settings › Desktop & Dock › Windows**.

## Project layout

```
Sources/ShiftZonesCore/   pure logic, no AppKit
  Zone.swift              ZoneRect (normalized 0…1, top-left origin), Zone, ZoneLayout
  ZoneGeometry.swift      zone → window frame (with spacing), hit testing, combining zones
  LayoutTemplate.swift    Columns / Rows / Grid / Priority templates
  ZoneEditing.swift       move / resize (linked edges, snapping) / split
  ZoneFile.swift          parsing (with per-line errors) and writing of the zones file
  LayoutStore.swift       zones of every display, file regeneration, default layouts
Sources/ShiftZones/       menu bar app
  AppDelegate.swift       menu bar, Accessibility permission, opening the editor and settings
  DragController.swift    detects a window drag and snaps the window to the zone
  OverlayController.swift transparent windows that show the zones while dragging
  ZoneEditor.swift        full-screen editor + toolbar
  ZoneCanvasView.swift    zone interaction and drawing in the editor
  SettingsView.swift      settings window (SwiftUI)
  Preferences.swift       preferences in UserDefaults and their defaults
  Accessibility.swift     reading and moving other apps' windows
  Screens.swift           stable display identifiers, coordinate conversions
  LayoutStore+AppKit.swift zones for an NSScreen, opening the zones file
  DirectoryWatcher.swift  watches the zones file (FSEvents)
  AppKitHelpers.swift     small AppKit and geometry helpers
Tests/CoreChecks/         checks run with `swift run CoreChecks`
scripts/                  build, run, local signing certificate, icon generation
```

### How dragging works

1. A global event monitor receives mouse down / drag / mouse up and modifier key changes.
2. On the first movement it looks up the window under the cursor (`AXUIElementCopyElementAtPosition`, falling
   back to `CGWindowList`) and records its frame; if the position changes but the size doesn't, the window is
   being dragged (not a text selection or a resize).
3. While the key is held it shows the zones right below the dragged window and highlights the one under the
   cursor.
4. On release it sets position and size through the Accessibility API (and applies them again after 100 ms
   for apps that finish their drag late).
