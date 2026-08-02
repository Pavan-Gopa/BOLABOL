# Graph Report - /Users/pavan/Documents/AI Projects/Blaboom  (2026-08-01)

## Corpus Check
- 12 files · ~8,974 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 243 nodes · 476 edges · 8 communities (7 shown, 1 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 2 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Branding and Packaging 1
- Branding and Packaging 2
- Branding and Packaging 3
- Branding and Packaging 4
- Branding and Packaging 5
- Branding and Packaging 6
- Branding and Packaging 7
- Branding and Packaging 8

## God Nodes (most connected - your core abstractions)
1. `NoteDetailView` - 54 edges
2. `OnboardingView` - 30 edges
3. `AppDelegate` - 28 edges
4. `ResultTextPanel` - 10 edges
5. `NoteGlossaryDraft` - 10 edges
6. `QuickTranslationWindowManager` - 9 edges
7. `SwiftUI` - 8 edges
8. `InAppSpectrumMeter` - 8 edges
9. `AppKit` - 7 edges
10. `VariantSegmentControl` - 7 edges

## Surprising Connections (you probably didn't know these)
- `build_and_run.sh script` --packages--> `Resources/Logos`  [EXTRACTED]
  script/build_and_run.sh → Package.swift
- `build_release_dmg.sh script` --packages--> `Resources/Logos`  [EXTRACTED]
  script/build_release_dmg.sh → Package.swift

## Import Cycles
- None detected.

## Communities (8 total, 1 thin omitted)

### Community 0 - "Branding and Packaging 1"
Cohesion: 0.09
Nodes (28): AnyShapeStyle, APIProviderKind, AudioRecording, Binding, BlaboomNote, Equatable, GlossaryDraftSaveRequest, GlossaryDraftSide (+20 more)

### Community 1 - "Branding and Packaging 2"
Cohesion: 0.10
Nodes (20): AccessibilityPermissionStore, LanguageChip, OnboardingView, AudioRecorder, Bool, Color, GeneralSettingsStore, GlossaryStore (+12 more)

### Community 2 - "Branding and Packaging 3"
Cohesion: 0.11
Nodes (12): NSApplication, NSApplicationDelegate, NSObject, NSStatusBarButton, NSStatusItem, NSWindow, NSWindowDelegate, AppDelegate (+4 more)

### Community 3 - "Branding and Packaging 4"
Cohesion: 0.07
Nodes (24): App, AppKit, AVFoundation, Element, KeyPath, NSScroller, ObjectiveC, Scene (+16 more)

### Community 4 - "Branding and Packaging 5"
Cohesion: 0.10
Nodes (13): PackageDescription, Resources/Logos, build_mlx_metallib(), open_app(), build_and_run.sh script, build_mlx_metallib(), codesign_release(), embed_swift_runtime() (+5 more)

### Community 5 - "Branding and Packaging 6"
Cohesion: 0.16
Nodes (12): Any, Carbon, Font, NativeBlaboomCore, NSEvent, NSPanel, QuickEscapePanel, QuickTranslationContentView (+4 more)

### Community 6 - "Branding and Packaging 7"
Cohesion: 0.13
Nodes (15): AppTextKey, Double, Float, PromptSlot, PromptTemplateStore, InAppSpectrumMeter, PolishingStatus, ResultPromptSlotSelector (+7 more)

## Knowledge Gaps
- **9 isolated node(s):** `PackageDescription`, `ObjectiveC`, `UniformTypeIdentifiers`, `AVFoundation`, `Notification.Name` (+4 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `NoteDetailView` connect `Branding and Packaging 1` to `Branding and Packaging 2`, `Branding and Packaging 7`?**
  _High betweenness centrality (0.250) - this node is a cross-community bridge._
- **Why does `AppDelegate` connect `Branding and Packaging 3` to `Branding and Packaging 4`?**
  _High betweenness centrality (0.237) - this node is a cross-community bridge._
- **Why does `OnboardingView` connect `Branding and Packaging 2` to `Branding and Packaging 1`, `Branding and Packaging 4`?**
  _High betweenness centrality (0.172) - this node is a cross-community bridge._
- **What connects `PackageDescription`, `ObjectiveC`, `UniformTypeIdentifiers` to the rest of the system?**
  _9 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Branding and Packaging 1` be split into smaller, more focused modules?**
  _Cohesion score 0.08700564971751412 - nodes in this community are weakly interconnected._
- **Should `Branding and Packaging 2` be split into smaller, more focused modules?**
  _Cohesion score 0.1006006006006006 - nodes in this community are weakly interconnected._
- **Should `Branding and Packaging 3` be split into smaller, more focused modules?**
  _Cohesion score 0.11428571428571428 - nodes in this community are weakly interconnected._