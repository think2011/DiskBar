# Desktop Disk Widget Design

## Goal

Add an optional desktop widget to DiskBar that shows the same disk capacity and live read/write speed information as the expanded popover, then verify the build on `think2011@192.168.27.20` with performance measurements.

## Decision

Use an in-app desktop `NSPanel`, not WidgetKit.

WidgetKit is optimized for timeline snapshots and system-managed refresh. It is a poor fit for 0.5-1.0 second live disk speed updates. DiskBar already owns a live `VolumeMonitor`, so an AppKit desktop-level panel can reuse the same data model, match the expanded popover styling, and keep refresh policy under app control.

## User Experience

- Add a "Desktop widget" toggle to the expanded popover controls.
- When enabled, show a small borderless card on the desktop.
- The card uses a compact desktop-specific layout: same storage title, one compact row per disk, a thin capacity bar, available-capacity summary, and prominent read/write speed labels.
- The expanded popover uses the same compact row layout so speed stays on the right in both places.
- The card can be dragged by its background and remembers its last frame.
- Disk rows remain clickable and open the corresponding Finder location.
- Disk rows can be dragged in the expanded popover to reorder the visible disks without adding a permanent handle or extra controls. The order is persisted and applies to both the popover and desktop widget. The desktop widget itself does not support row dragging because its whole card is draggable for positioning.
- The desktop widget is intended to sit above desktop icons and below normal application windows.

## Refresh And Performance Policy

- Capacity and volume enumeration stay low frequency on the existing 3 second timer.
- Speed sampling runs only while either the popover or desktop widget is visible.
- The popover keeps the more responsive 0.5 second speed cadence.
- A widget-only session uses a 1.0 second speed cadence to reduce permanent CPU and UI churn.
- The speed timer samples IOKit counters only; it must not refresh capacity every tick.
- UI updates are limited to at most four visible volumes.
- The desktop widget stays substantially smaller than the expanded popover. On the remote 4-disk setup it should be roughly 270 px wide and about 220 px tall.

This means the widget can show live disk speed without frequent capacity reads. The main cost becomes a small SwiftUI text refresh once per second, which is measurable and acceptable if remote stress tests show low CPU.

## Testing

- Build the app locally with `./build.sh dist`.
- Build a local stress helper from `tools/stress.swift` plus the monitor sources.
- Deploy the app and stress helper to `think2011@192.168.27.20`.
- Enable the desktop widget with app defaults, launch the app in the remote GUI session, and capture a screenshot.
- Run realistic stress tests for widget-only 1.0 second speed sampling and popover-like 0.5 second speed sampling.
- Use CPU percentage and sampling latency to decide whether the widget should default to 1.0 second refresh or expose a trade-off.
