# Desktop Disk Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add an optional desktop disk widget to DiskBar and verify it on the remote Mac with performance stress tests.

**Architecture:** Keep one shared `VolumeMonitor` in `AppDelegate`. Add persisted app settings, a desktop `NSPanel` controller, and one compact reusable SwiftUI disk row list shared by the popover and desktop widget. Replace the current popover speed timer with one adaptive speed timer: 0.5 seconds while the popover is open, 1.0 second when only the desktop widget is visible, stopped when neither is visible.

**Tech Stack:** Swift, SwiftUI, AppKit `NSPanel`, Combine, IOKit, shell deployment over SSH.

---

### Task 1: Persist The Desktop Widget Toggle

**Files:**
- Create: `Sources/AppSettings.swift`
- Modify: `Sources/DetailView.swift`

- [x] Add `AppSettings` as an `ObservableObject` singleton with a `desktopWidgetEnabled` boolean persisted to `UserDefaults` under `DesktopWidgetEnabled`.
- [x] In `DetailView`, observe `AppSettings.shared` and add a checkbox toggle labeled `桌面组件` / `Desktop widget`.
- [x] Keep the footer compact by using two rows: launch/widget toggles on the first row, language/quit controls on the second row.
- [x] Build with `./build.sh dist`.

### Task 2: Add The Desktop Widget Window

**Files:**
- Create: `Sources/DesktopWidgetWindow.swift`
- Modify: `Sources/DetailView.swift`

- [x] Add `DesktopWidgetView` as a compact lightly transparent card with one row per disk, thin usage bars, available capacity, and prominent speed labels.
- [x] Replace the popover disk rows with the same compact row list so speed appears on the right in both surfaces.
- [x] Add hidden row drag/drop sorting in the popover only; persist order in `AppSettings.volumeOrder` and apply it from `VolumeMonitor.refresh()` so the desktop widget follows the saved order without row-level dragging.
- [x] Add `DesktopWidgetController` that owns a borderless non-activating `NSPanel`.
- [x] Put the panel at `CGWindowLevelKey.desktopIconWindow + 1`, with `canJoinAllSpaces`, `stationary`, and `ignoresCycle`.
- [x] Make the panel draggable by background and persist its frame under `DesktopWidgetFrame`.
- [x] Expose `setVisible(_:)`, `isShown`, and `onVisibilityChange`.
- [x] Build with `./build.sh dist`.

### Task 3: Share And Throttle Live Speed Sampling

**Files:**
- Modify: `Sources/main.swift`

- [x] Import Combine and hold `AppSettings.shared`, `DesktopWidgetController`, and a settings cancellable.
- [x] Show or hide the desktop widget when `desktopWidgetEnabled` changes.
- [x] Replace the popover-only speed timer with an adaptive timer.
- [x] Use a 0.5 second interval when the popover is visible.
- [x] Use a 1.0 second interval when only the widget is visible.
- [x] Stop the speed timer when both popover and widget are hidden.
- [x] Remove `monitor.refresh()` from the speed timer tick so capacity reads stay on the 3 second timer.
- [x] Build with `./build.sh dist`.

### Task 4: Add Stress Tool And Documentation

**Files:**
- Create: `tools/stress.swift`
- Modify: `README.md`

- [x] Add a stress helper that runs realistic timer loops for configurable duration, speed interval, and capacity interval.
- [x] Print wall time, process CPU seconds, process CPU percentage, volume count, speed entry count, and p50/p95/max latency for capacity and speed samples.
- [x] Update README feature text to mention the optional desktop widget and the 1 second widget speed cadence.
- [x] Build the stress helper with `swiftc -O tools/stress.swift Sources/VolumeMonitor.swift Sources/IOStats.swift Sources/AppSettings.swift -framework IOKit -framework Combine -o /tmp/diskbar-stress`.

### Task 5: Remote Verification

**Files:**
- No source changes.

- [x] Build locally with `./build.sh dist`.
- [x] Copy `dist/DiskBar.app` and `/tmp/diskbar-stress` to `think2011@192.168.27.20:/tmp/`.
- [x] Stop the existing remote DiskBar process, enable `DesktopWidgetEnabled`, launch `/tmp/DiskBar.app`, and verify the desktop window through CoreGraphics window listing plus offscreen preview PNGs.
- [x] Run `/tmp/diskbar-stress --duration 60 --speed-interval 1 --capacity-interval 3`.
- [x] Run `/tmp/diskbar-stress --duration 60 --speed-interval 0.5 --capacity-interval 3`.
- [x] Report whether the 1 second widget cadence is acceptable, and when 0.5 second always-on refresh would be worth the extra cost.
