# Minecraft PE 0.6.1 — native OS X Mavericks (10.9.5) port

A native macOS build of Minecraft Pocket Edition 0.6.1. The original
cross-platform C++ engine is left unchanged; this project adds an
AppKit / Cocoa front-end and a desktop OpenGL 2.1 compatibility shim
so the game runs as a regular `.app` bundle on OS X 10.9 (Mavericks).

This project is a descendant of
[TimofeyLednev/Minecraft-PE-0.6.1-iOS-3.1](https://github.com/TimofeyLednev/Minecraft-PE-0.6.1-iOS-3.1),
which itself adapts the original Minecraft PE 0.6.1 source to iPhone OS
3.1 and OpenGL ES 1.1. The Windows / Raspberry Pi / Android / iOS
back-ends are kept in place — only the macOS target is new.

## Building

### Requirements

- OS X 10.9 Mavericks (any 10.9.x patch level)
- Xcode 5.1.1 or 6.x command-line tools (provides `clang`, libc++ and
  the macOS 10.9 SDK)
- GNU `make`

### Build & run

```sh
cd handheld/project/osxproj
make            # debug build  -> build/Minecraft\ PE.app
make BUILD=release
make run        # build + open the .app
make clean
```

The build produces a self-contained `Minecraft PE.app` bundle with
the contents of `handheld/data/` staged into `Contents/Resources/`.
World saves and options are stored under
`~/Library/Application Support/MinecraftPE/`.

## What's in the macOS port

- `handheld/src/client/renderer/gles.h` — routes Apple-but-not-iOS
  builds through desktop OpenGL 2.1 from `OpenGL.framework`, with thin
  compatibility macros (`glFogx`, `glOrthof`, `glClearDepthf`, …) for
  the GLES-1.1-style fixed-function calls the engine still makes.
- `handheld/src/AppPlatform_macOS.{h,mm}` — `AppPlatform`
  implementation backed by AppKit / CoreGraphics:
  - texture loading via `NSImage` + `CGBitmapContext`
  - asset reading via `NSBundle`, with a dev-mode fallback that looks
    for `data/images/...` next to the .app
  - dialogs via `NSAlert` with an optional `NSTextField` accessory
    (covers `DIALOG_CREATE_NEW_WORLD`, `DIALOG_RENAME_MP_WORLD`,
    `DIALOG_SET_USERNAME`, …)
  - real pixels-per-mm from `NSScreen` + `CGDisplayScreenSize`
  - option strings backed by `NSUserDefaults`
- `handheld/project/osxproj/MinecraftMacApp/` — Cocoa entry point:
  - `main.mm`, `MinecraftMacAppDelegate.{h,mm}` — `NSApplication`
    delegate, menu bar, window with title / close / resize
  - `MinecraftMacGLView.{h,mm}` — `NSOpenGLView` subclass owning the
    engine, driving update / render with an `NSTimer` at 60 Hz
    (fires during window resize / modal panels too); `kVK_*` →
    engine key codes; mouse + scroll-wheel forwarding to
    `Mouse` / `Multitouch` / `Keyboard`
  - `Info.plist` (`LSMinimumSystemVersion = 10.9`,
    `NSHighResolutionCapable`)
- `handheld/project/osxproj/Makefile` — builds the `.app` with
  `clang++ -mmacosx-version-min=10.9 -arch x86_64 -std=c++98 -fno-rtti`.

## Input mapping

| Action                       | macOS input                              |
| ---------------------------- | ---------------------------------------- |
| iOS one-finger tap           | Left mouse button                        |
| Second-finger context tap    | Right mouse button                       |
| Camera                       | Mouse movement                           |
| Hot-bar scroll               | Scroll wheel                             |
| Walk / strafe                | `W` `A` `S` `D`                          |
| Jump / sneak                 | `Space` / `Shift`                        |
| Pause                        | `Esc`                                    |
| Chat                         | `T`                                      |
| Inventory                    | `Tab`                                    |

## Current limitations

- Sound is not wired up — the engine's `SoundEngine` already guards
  most of its sound-table population with `#if !defined(__APPLE__)`,
  so the game runs silent on macOS the same way it does on iOS at
  this point. Wiring up `AVAudioPlayer` / OpenAL is a separate change.
- The settings dialog (`DIALOG_MAINMENU_OPTIONS`) currently shows an
  `NSAlert` pointing at `NSUserDefaults`. A richer `NSWindow`-based
  settings panel can be added later without touching the engine.
- Networking compiles in but hasn't been smoke-tested against the
  iOS / Win32 ports yet.

## Other platforms

The original iOS / Windows / Raspberry Pi projects under
`handheld/project/` are kept intact so this repository can also build
those targets unchanged. See `handheld/project/iosproj/` for the iOS
project (Xcode 4.1, iOS 4.3 SDK target) and
`handheld/project/win32/` for the Windows build.

## Credits

- Mojang AB — original Minecraft PE 0.6.1 source.
- [@TimofeyLednev](https://github.com/TimofeyLednev) — iOS 3.1 +
  OpenGL ES 1.1 back-port.
- [@yefengeeeeeeeeeee](https://github.com/yefengeeeeeeeeeee) —
  iPad xib fixes for Xcode 4.1.
