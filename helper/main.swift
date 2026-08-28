// omacosy-helper — tiny compiled utility replacing four brew dependencies
// (cliclick, desktoppr, switchaudio-osx, blueutil):
//   cursor                  print the cursor position as "x,y" (CG top-left)
//   cursor set <x> <y>      warp it there (no synthetic movement, so
//                           focus-follows-mouse cannot react)
//   displays                per display (arrangement order): "index<TAB>notched"
//   wallpaper <path>        set the desktop picture on every screen
//   audio list              output devices: "*<TAB>name" (current) / "-<TAB>name"
//   audio set <name>        make <name> the default output device
//   bt power                print bluetooth power state (0/1)
//   bt power <on|off|toggle>
//   bt devices              paired devices: "<1|0 connected><TAB>address<TAB>name<TAB>kind"
//                           kind is a coarse class-of-device keyword
//                           (headphones/speaker/mic/keyboard/pointer/
//                           combo/phone/watch/device) for popup icons
//   bt connect <address> / bt disconnect <address>
//   input-age               seconds since the last deliberate user input
//                           (keys/clicks/scroll), for the focus guard
//   frames <id>...          "<id> <x> <y> <w> <h>" per window that still
//                           exists, for telling a layout command that
//                           moved something from one that silently did not
//   brightness              print the built-in display's brightness (0-100)
//   brightness set <0-100>  set it (DisplayServices — built-in/Apple
//                           displays only; external DDC is out of scope)
//   nightshift              print night shift state (on/off)
//   nightshift <on|off|toggle>
//   lock                    lock the screen NOW (SACLockScreenImmediate)
// Built by install.sh with swiftc (present wherever Homebrew is).
// Bluetooth subcommands need the Bluetooth privacy permission of the
// *responsible* process (sketchybar, for bar plugins).
import AppKit
import CoreAudio
import IOBluetooth

// private but stable power API — the same symbols blueutil links
@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
func BTGetPower() -> Int32
@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
func BTSetPower(_ state: Int32)

// DisplayServices (private) — the same calls Control Center makes;
// covers the built-in panel and Apple externals
@_silgen_name("DisplayServicesGetBrightness")
func DSGetBrightness(_ display: CGDirectDisplayID, _ value: UnsafeMutablePointer<Float>) -> Int32
@_silgen_name("DisplayServicesSetBrightness")
func DSSetBrightness(_ display: CGDirectDisplayID, _ value: Float) -> Int32

func builtinDisplayID() -> CGDirectDisplayID {
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var n: UInt32 = 0
    guard CGGetActiveDisplayList(8, &ids, &n) == .success else { return CGMainDisplayID() }
    for i in 0..<Int(n) where CGDisplayIsBuiltin(ids[i]) != 0 {
        return ids[i]
    }
    return CGMainDisplayID()
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

// --- CoreAudio ---------------------------------------------------------

func audioProperty(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}

func defaultOutputDevice() -> AudioDeviceID {
    var addr = audioProperty(kAudioHardwarePropertyDefaultOutputDevice)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

func outputDevices() -> [AudioDeviceID] {
    var addr = audioProperty(kAudioHardwarePropertyDevices)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.filter { id in
        var streamsAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var streamsSize = UInt32(0)
        AudioObjectGetPropertyDataSize(id, &streamsAddr, 0, nil, &streamsSize)
        return streamsSize > 0
    }
}

func deviceName(_ id: AudioDeviceID) -> String {
    var addr = audioProperty(kAudioObjectPropertyName)
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    withUnsafeMutablePointer(to: &name) { ptr in
        _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
    }
    return name as String
}

// --- dispatch ----------------------------------------------------------

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "cursor":
    // `cursor set X Y` warps without synthesising movement, which is
    // exactly what a script wants: focus-follows-mouse is movement-gated,
    // so placing the pointer this way cannot make it steal focus.
    if args.count > 2, args[2] == "set" {
        guard args.count > 4, let x = Double(args[3]), let y = Double(args[4])
        else { fail("usage: cursor set <x> <y>") }
        CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
        break
    }
    guard let e = CGEvent(source: nil) else { exit(1) }
    print("\(Int(e.location.x)),\(Int(e.location.y))")

case "displays":
    // arrangement-ordered (left to right, matching AeroSpace/sketchybar
    // numbering): "<index><TAB><1 if notched else 0>"
    let screens = NSScreen.screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
    for (i, scr) in screens.enumerated() {
        let notched = scr.safeAreaInsets.top > 0 ? 1 : 0
        print("\(i + 1)\t\(notched)")
    }

case "wallpaper":
    guard args.count > 2 else { fail("usage: wallpaper <path> | wallpaper get") }
    // `get` prints each screen's current wallpaper path in arrangement
    // order — install.sh records these so uninstall.sh can put the
    // pre-omacosy picture back instead of leaving the theme wallpaper
    // as a souvenir.
    if args[2] == "get" {
        for screen in NSScreen.screens.sorted(by: { $0.frame.origin.x < $1.frame.origin.x }) {
            print(NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? "")
        }
        break
    }
    let url = URL(fileURLWithPath: args[2])
    var failures = 0
    for screen in NSScreen.screens {
        do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) }
        catch { failures += 1 }
    }
    exit(failures == 0 ? 0 : 1)

case "nightshift":
    // CBBlueLightClient (private CoreBrightness) — what Control Center
    // itself calls. Only the leading `active`/`enabled` fields of the
    // status struct are read; the rest is layout padding per the OSS
    // `nightlight` tool.
    guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
        let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type
    else { fail("nightshift: CoreBrightness unavailable") }
    let client = cls.init()
    struct BLStatus {
        var active: ObjCBool = false
        var enabled: ObjCBool = false
        var sunSchedulePermitted: ObjCBool = false
        var mode: Int32 = 0
        var schedule: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
        var disableFlags: UInt64 = 0
        var available: ObjCBool = false
    }
    func blEnabled() -> Bool {
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard let m = class_getInstanceMethod(cls, sel) else { return false }
        typealias GetFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let f = unsafeBitCast(method_getImplementation(m), to: GetFn.self)
        var st = BLStatus()
        _ = withUnsafeMutablePointer(to: &st) { f(client, sel, UnsafeMutableRawPointer($0)) }
        return st.enabled.boolValue
    }
    func blSet(_ on: Bool) {
        let sel = NSSelectorFromString("setEnabled:")
        guard let m = class_getInstanceMethod(cls, sel) else { fail("nightshift: setEnabled missing") }
        typealias SetFn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let f = unsafeBitCast(method_getImplementation(m), to: SetFn.self)
        _ = f(client, sel, on)
    }
    switch args.count > 2 ? args[2] : "status" {
    case "on": blSet(true)
    case "off": blSet(false)
    case "toggle": blSet(!blEnabled())
    case "status": break
    default: fail("usage: nightshift [on|off|toggle]")
    }
    print(blEnabled() ? "on" : "off")

case "lock":
    // `pmset displaysleepnow` was standing in for this and is not a lock
    // at all: it darkens the panel, and whether that ever locks depends
    // on the screenLock delay — 300s on the author's machine, so the
    // screen came back unlocked. SACLockScreenImmediate is what the
    // native Lock Screen menu item calls, and it ignores that delay.
    guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
        let sym = dlsym(h, "SACLockScreenImmediate")
    else { fail("lock: SACLockScreenImmediate unavailable") }
    typealias LockFn = @convention(c) () -> Int32
    let rc = unsafeBitCast(sym, to: LockFn.self)()
    if rc != 0 { fail("lock: SACLockScreenImmediate returned \(rc)") }

case "brightness":
    let display = builtinDisplayID()
    if args.count > 3, args[2] == "set" {
        guard let pct = Int(args[3]), (0...100).contains(pct) else {
            fail("usage: brightness set <0-100>")
        }
        guard DSSetBrightness(display, Float(pct) / 100.0) == 0 else {
            fail("brightness: set failed (unsupported display?)")
        }
    }
    var level: Float = -1
    guard DSGetBrightness(display, &level) == 0, level >= 0 else {
        fail("brightness: unreadable (unsupported display?)")
    }
    print(Int((level * 100).rounded()))

case "input-age":
    // seconds since the last DELIBERATE user input (keys, clicks,
    // scroll — not mouse motion). The focus guard uses this to tell a
    // user-driven workspace switch from an app yanking focus to
    // itself.
    let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown,
        .otherMouseDown, .scrollWheel]
    let age = types
        .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
        .min() ?? .infinity
    print(String(format: "%.2f", age))

case "omniwm-overview-close":
    // Swipe-down's half of the overview gesture. OmniWM rejects every
    // IPC command while its overview is open (ignored_overview), so no
    // gesture can close it through the socket — but the overview
    // listens for Escape. Post one, guarded on the overview actually
    // being on screen (an OmniWM-owned window tall enough to be the
    // panel, not the workspace bar), so a stray swipe-down can never
    // fire Escape into whatever app is focused.
    //
    // CGEventPost needs Accessibility, judged by the RESPONSIBLE
    // process: run from omacosy-gesture's handler (which holds
    // the grant) this works; run from a bare shell it may not.
    guard let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { exit(1) }
    let overviewUp = wins.contains { w in
        (w[kCGWindowOwnerName as String] as? String) == "OmniWM"
            && ((w[kCGWindowBounds as String] as? [String: CGFloat])?["Height"] ?? 0) > 400
    }
    guard overviewUp else { exit(0) }
    // don't post Escape — synthetic key events depend on the caller's
    // Accessibility responsibility and OmniWM ignored them in testing.
    // The overview dismisses ITSELF when another app takes focus (its
    // own documented behavior), and activating an app needs no
    // permission: hand focus to the topmost normal window's app.
    for w in wins {
        guard (w[kCGWindowLayer as String] as? Int) == 0,
            let pid = w[kCGWindowOwnerPID as String] as? pid_t,
            let app = NSRunningApplication(processIdentifier: pid) else { continue }
        app.activate()
        break
    }

case "split-hint":
    // Hyprland's dwindle splits the focused window along its longer
    // edge; AeroSpace has no such layout and no window geometry in its
    // config language, so the direction is chosen here and applied with
    // `split` while the next window still does not exist. AeroSpace
    // then places that window correctly on its first pass — correcting
    // the tree afterwards is what made the screen lay out twice.
    //
    // Driven by aerospace.toml's on-focus-changed hook, which names the
    // window in AEROSPACE_WINDOW_ID — hover focus included: AeroSpace
    // does track the focus omacosy-ffm moves. The frame comes from the
    // window list rather than the Accessibility API, so this needs no
    // grant of its own.
    //
    // `--window-id` rather than "the focused window": this runs a few
    // hundred ms after the focus change, and a window that opens inside
    // that gap takes focus with it. Naming the window keeps a late hint
    // on the one it was computed for instead of retargeting the
    // newcomer.
    guard let idStr = ProcessInfo.processInfo.environment["AEROSPACE_WINDOW_ID"],
        let wid = UInt32(idStr) else { exit(0) }
    // A NEW window fires this hook too (it takes focus on open), and at
    // that moment its frame is still wherever the app spawned it —
    // AeroSpace has not tiled it yet. Waiting for the frame to settle
    // costs ~400ms, and spamming Super+Enter opens windows faster than
    // that, so waiting loses the race and the spiral falls apart.
    //
    // So new windows are not read, they are PREDICTED. Splitting a slot
    // makes both halves' geometry known without looking: split a
    // 1708x1389 slot vertically and the next slot is 1708x694. A state
    // file carries the last hinted window's slot and direction; a hook
    // for a NEWER window id (CGWindowIDs are issued in increasing
    // order) chains off it instantly. The hint then lands ~45ms after
    // the focus change — faster than any app can open its next window.
    //
    // Refocusing an EXISTING window (hover, keyboard) reads the frame
    // directly: it already sits in its slot, no waiting needed. The
    // slow settle-wait survives only as the fallback when there is no
    // fresh state to chain from (first window in a burst).
    // State is one line: "wid w h ts". A 3s TTL bounds how stale a
    // chain can get (manual resizes, closes, and workspace switches
    // invalidate predictions; a burst of opens never lives that long).
    func frame(_ id: UInt32) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
            let b = list.first?[kCGWindowBounds as String] as? [String: CGFloat],
            let x = b["X"], let y = b["Y"],
            let w = b["Width"], let h = b["Height"] else { return nil }
        return (x, y, w, h)
    }
    let splitWidthMultiplier: CGFloat = 1.4
    let uid = getuid()
    let statePath = "/tmp/omacosy-split-state-\(uid)"
    let seenPath = "/tmp/omacosy-split-seen-\(uid)"
    let now = Date().timeIntervalSince1970

    // NEW vs REFOCUSED is the whole ballgame, and a window id alone
    // cannot answer it: ids only grow, so "id higher than the last one
    // hinted" is also true of simply focusing a newer window that has
    // been open for hours — which had prediction inventing a slot for a
    // window sitting in plain sight. Every id we have hinted is
    // remembered instead, so newness is a fact rather than a guess.
    var seen = (try? String(contentsOfFile: seenPath, encoding: .utf8))?
        .split(separator: "\n").map(String.init) ?? []
    let isNew = !seen.contains(idStr)

    // The focused workspace, as aerospace's own workspace hook records
    // it — a chain must not span a workspace switch, where the previous
    // window's slot says nothing about the new window's.
    let ws = (try? String(contentsOfFile: "/tmp/omacosy-bar-ws", encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    // State is one line: "wid w h ts ws".
    var state: (wid: UInt32, w: CGFloat, h: CGFloat, ws: String)?
    if let line = try? String(contentsOfFile: statePath, encoding: .utf8) {
        let f = line.split(separator: " ").map(String.init)
        if f.count >= 4, let sw = UInt32(f[0]),
            let sww = Double(f[1]), let shh = Double(f[2]) {
            state = (sw, CGFloat(sww), CGFloat(shh), f.count >= 5 ? f[4] : ws)
        }
    }

    // A chain is trustworthy when the window it came from is STILL
    // sitting where we left it. Checking that beats the wall-clock TTL
    // this replaced: three seconds declared a chain dead between two
    // deliberate Super+Return presses — the ordinary human pace — and
    // dropped every second window onto the measure path below, which is
    // exactly where it was mis-measured. Age is not the risk; a layout
    // that moved underneath is, and that is what this sees.
    //
    // Either frame is consistent: the recorded slot if the split has
    // not landed yet, or the half it becomes once it has. The tolerance
    // covers gaps and rounding.
    func chainValid(_ s: (wid: UInt32, w: CGFloat, h: CGFloat, ws: String)) -> Bool {
        guard s.ws == ws, wid > s.wid, let f = frame(s.wid) else { return false }
        let half: (CGFloat, CGFloat) = s.w >= s.h * splitWidthMultiplier
            ? (s.w / 2, s.h) : (s.w, s.h / 2)
        let tol: CGFloat = 16
        return (abs(f.2 - s.w) <= tol && abs(f.3 - s.h) <= tol)
            || (abs(f.2 - half.0) <= tol && abs(f.3 - half.1) <= tol)
    }

    var w: CGFloat
    var h: CGFloat
    var how: String
    if isNew, let s = state, chainValid(s) {
        // a new window: its slot is the half left over from the split
        // already issued on the window it opened next to
        if s.w >= s.h * splitWidthMultiplier { w = s.w / 2; h = s.h } else { w = s.w; h = s.h / 2 }
        how = "predicted"
    } else if isNew {
        // a new window with no chain to ride (first of a workspace, or
        // a layout that moved): wait for AeroSpace to tile it. A new
        // window MUST move before its frame means anything — measured
        // untiled it reads as the app's own spawn size, and Ghostty now
        // spawns deliberately small. Quiet is also not enough on its
        // own: a window passes through intermediate frames on the way
        // to its slot and can hold one across two samples, which is how
        // a half-width slot got measured full-width and split the wrong
        // way. Three quiet samples after a move, not one.
        var sample = frame(wid)
        var moved = false
        var stable = 0
        for tick in 1...28 {
            usleep(75_000)
            guard let next = frame(wid) else { break }
            if let a = sample, next != a { moved = true; stable = 0 } else { stable += 1 }
            sample = next
            if moved && stable >= 3 { break }
            if !moved && tick >= 8 { break } // never tiled (floating): take it
        }
        guard let f = sample else { exit(0) }
        (w, h) = (f.2, f.3)
        how = moved ? "settled" : "static"
    } else {
        // already open and already in its slot: read it, no waiting
        guard let f = frame(wid) else { exit(0) }
        (w, h) = (f.2, f.3)
        how = "read"
    }
    // Direction: Hyprland's rule is `stack when h * multiplier > w`
    // (dwindle:split_width_multiplier, default 1.0). At 1.0 an
    // ultrawide's half-slot (1712x1389) is still wider than tall, so
    // the spiral goes side-by-side twice before it ever stacks. 1.4
    // makes that half-slot stack first, which restores the 16:9
    // left/down/left cadence on a 3440-wide display without changing
    // behavior on displays where the half is already taller than wide.
    let dir = w >= h * splitWidthMultiplier ? "horizontal" : "vertical"
    let aerospaceBin = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "aerospace"
    let split = Process()
    split.executableURL = URL(fileURLWithPath: aerospaceBin)
    split.arguments = ["split", "--window-id", idStr, dir]
    split.standardError = FileHandle.nullDevice
    try? split.run()
    split.waitUntilExit()
    try? "\(wid) \(w) \(h) \(now) \(ws)".write(toFile: statePath, atomically: true, encoding: .utf8)
    // remember this id so the next hook for it is read, not predicted.
    // Bounded: the tail is all a chain can ever reach back to.
    if isNew {
        seen.append(idStr)
        if seen.count > 400 { seen = Array(seen.suffix(200)) }
        try? seen.joined(separator: "\n").write(toFile: seenPath, atomically: true, encoding: .utf8)
    }
    if let d = "\(Date().timeIntervalSince1970) wid=\(idStr) \(Int(w))x\(Int(h)) (\(how)) -> \(dir == "horizontal" ? "h" : "v") rc=\(split.terminationStatus)\n".data(using: .utf8),
        let fh = FileHandle(forWritingAtPath: "/tmp/omacosy-split-hint.log") ?? {
            FileManager.default.createFile(atPath: "/tmp/omacosy-split-hint.log", contents: nil)
            return FileHandle(forWritingAtPath: "/tmp/omacosy-split-hint.log")
        }() {
        fh.seekToEndOfFile(); fh.write(d); fh.closeFile()
    }

case "audio":
    let sub = args.count > 2 ? args[2] : "list"
    if sub == "list" {
        let current = defaultOutputDevice()
        for id in outputDevices() {
            print("\(id == current ? "*" : "-")\t\(deviceName(id))")
        }
    } else if sub == "set", args.count > 3 {
        guard let id = outputDevices().first(where: { deviceName($0) == args[3] }) else {
            fail("audio: no output device named '\(args[3])'")
        }
        var addr = audioProperty(kAudioHardwarePropertyDefaultOutputDevice)
        var dev = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &dev) == noErr else {
            fail("audio: failed to set default output")
        }
    } else {
        fail("usage: audio list | audio set <name>")
    }

case "bt":
    let sub = args.count > 2 ? args[2] : ""
    switch sub {
    case "power":
        if args.count > 3 {
            let want: Int32
            switch args[3] {
            case "on": want = 1
            case "off": want = 0
            case "toggle": want = BTGetPower() == 0 ? 1 : 0
            default: fail("usage: bt power [on|off|toggle]")
            }
            BTSetPower(want)
            // the preference call is async; give it a moment
            for _ in 0..<20 where BTGetPower() != want { usleep(100_000) }
        }
        print(BTGetPower())
    case "devices":
        // Coarse class-of-device keyword from the CoD major/minor
        // fields (Bluetooth Assigned Numbers). Only buckets the popup
        // can pick an icon for — everything else is "device".
        func kind(_ d: IOBluetoothDevice) -> String {
            switch d.deviceClassMajor {
            case 0x04: // audio/video
                switch d.deviceClassMinor {
                case 0x04: return "mic"
                case 0x05, 0x07, 0x08, 0x0A: return "speaker" // loudspeaker / portable / car / hifi
                default: return "headphones" // headset / hands-free / headphones
                }
            case 0x05: // peripheral: bits 4-5 of the minor field
                switch d.deviceClassMinor & 0x30 {
                case 0x10: return "keyboard"
                case 0x20: return "pointer"
                case 0x30: return "combo"
                default: return "device"
                }
            case 0x02: return "phone"
            case 0x07: return "watch"
            default: return "device"
            }
        }
        for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] {
            let name = d.name ?? "unknown"
            let addr = d.addressString ?? "?"
            print("\(d.isConnected() ? 1 : 0)\t\(addr)\t\(name)\t\(kind(d))")
        }
    case "connect", "disconnect":
        guard args.count > 3 else { fail("usage: bt \(sub) <address>") }
        guard let d = IOBluetoothDevice(addressString: args[3]) else { fail("bt: bad address") }
        let status = sub == "connect" ? d.openConnection() : d.closeConnection()
        exit(status == kIOReturnSuccess ? 0 : 1)
    default:
        fail("usage: bt power [on|off|toggle] | bt devices | bt connect <addr> | bt disconnect <addr>")
    }

case "frames":
    // Geometry for named windows, in one call. AeroSpace reports what it
    // INTENDS ("already in the requested tiling mode") but a rotation of a
    // container holding a single child moves nothing on screen, and the
    // exit code is 0 either way — so the only honest test of whether a
    // layout command did anything is the pixels before and after.
    // Ids that have closed are skipped rather than faked.
    for a in args.dropFirst(2) {
        guard let id = UInt32(a),
            let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
            let b = list.first?[kCGWindowBounds as String] as? [String: CGFloat],
            let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
        else { continue }
        print("\(a) \(Int(x)) \(Int(y)) \(Int(w)) \(Int(h))")
    }

default:
    fail("usage: omacosy-helper cursor | displays | wallpaper <path> | audio ... | bt ... | brightness [set <0-100>] | input-age | frames <id>...")
}
