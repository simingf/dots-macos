// Picks the target window-id when crossing aerospace monitor/workspace edges.
//
// `list-windows` sorts alphabetically by app/title rather than tree/spatial
// order, so we read window frames from CoreGraphics and pick the spatially
// correct edge ourselves. This binary also walks the monitor list (in spatial
// order) to find the next non-empty target — keeps all the cross-monitor
// logic in one place so the wrapper script stays minimal.
//
// Usage: find-edge-window <left|right|up|down> <monitors-file> <windows-file>
//   monitors-file: aerospace list-monitors output, one monitor-id per line in
//                  spatial order.
//   windows-file:  aerospace list-windows --all output, TAB-separated:
//                  window-id, monitor-id, workspace, ws-is-visible, ws-is-focused
//
// Direction → which window on the destination monitor we want:
//   right -> leftmost   (smallest x)
//   left  -> rightmost  (largest x)
//   down  -> topmost    (smallest y)
//   up    -> bottommost (largest y)

import Cocoa

guard CommandLine.arguments.count >= 4 else { exit(2) }
let dir = CommandLine.arguments[1]
let monitorsPath = CommandLine.arguments[2]
let windowsPath = CommandLine.arguments[3]

func readLines(_ path: String) -> [String] {
    guard let data = FileManager.default.contents(atPath: path),
          let s = String(data: data, encoding: .utf8) else { return [] }
    return s.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
}

let monitors = readLines(monitorsPath)
guard !monitors.isEmpty else { exit(0) }

struct Win {
    let id: Int
    let monitor: String
    let workspace: String
    let wsVisible: Bool
    let wsFocused: Bool
}

var allWindows: [Win] = []
for line in readLines(windowsPath) {
    let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 5, let id = Int(parts[0]) else { continue }
    allWindows.append(Win(
        id: id,
        monitor: parts[1],
        workspace: parts[2],
        wsVisible: parts[3] == "true",
        wsFocused: parts[4] == "true",
    ))
}

guard let focused = allWindows.first(where: { $0.wsFocused }),
      let startIdx = monitors.firstIndex(of: focused.monitor) else { exit(0) }

let n = monitors.count

func step(_ i: Int) -> Int {
    switch dir {
    case "right", "down": return (i + 1) % n
    case "left", "up":    return (i - 1 + n) % n
    default: return i
    }
}

// Walk monitors in dir; pick the first whose visible workspace has windows.
// After n hops we land back on the source monitor — its workspace contains
// the focused window, so it's guaranteed non-empty (handles single-monitor
// wrap and "all other monitors empty" cases).
var idx = startIdx
var candidates: [Win] = []
for _ in 0..<n {
    idx = step(idx)
    let mon = monitors[idx]
    guard let visWs = allWindows.first(where: { $0.monitor == mon && $0.wsVisible })?.workspace else { continue }
    let inWs = allWindows.filter { $0.workspace == visWs }
    if !inWs.isEmpty { candidates = inWs; break }
}
guard !candidates.isEmpty else { exit(0) }

let candidateIds = Set(candidates.map(\.id))

guard let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { exit(1) }

struct Frame { let id: Int; let x: CGFloat; let y: CGFloat }

var frames: [Frame] = []
for entry in info {
    guard let id = entry[kCGWindowNumber as String] as? Int, candidateIds.contains(id) else { continue }
    guard let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
          let x = bounds["X"], let y = bounds["Y"] else { continue }
    frames.append(Frame(id: id, x: x, y: y))
}
guard !frames.isEmpty else { exit(0) }

let pick: Frame?
switch dir {
case "right": pick = frames.min { $0.x < $1.x }
case "left":  pick = frames.max { $0.x < $1.x }
case "down":  pick = frames.min { $0.y < $1.y }
case "up":    pick = frames.max { $0.y < $1.y }
default:      exit(2)
}

if let p = pick { print(p.id) }
