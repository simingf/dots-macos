// Picks the target window-id when crossing aerospace monitor/workspace edges,
// or when doing strict spatial up/down focus within a workspace.
//
// Two modes:
//
// Cross-monitor (left/right):
//   find-edge-window <left|right> <monitors-file> <windows-file>
//   Walks monitors in direction, picks the spatially-nearest edge window on
//   the destination monitor via CoreGraphics frames.
//
// Spatial within-workspace (up/down):
//   find-edge-window --spatial <up|down> <focused-window-id> <workspace-windows-file>
//   Finds a window actually above/below the focused window (>50px Y offset).
//   Prints nothing if no valid target exists (all windows are in a horizontal row).

import Cocoa

struct Frame { let id: Int; let x: CGFloat; let y: CGFloat; let h: CGFloat }

func cgFrames(for ids: Set<Int>) -> [Frame] {
    guard let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
    var result: [Frame] = []
    for entry in info {
        guard let id = entry[kCGWindowNumber as String] as? Int, ids.contains(id) else { continue }
        guard let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"], let h = bounds["Height"] else { continue }
        result.append(Frame(id: id, x: x, y: y, h: h))
    }
    return result
}

func readLines(_ path: String) -> [String] {
    guard let data = FileManager.default.contents(atPath: path),
          let s = String(data: data, encoding: .utf8) else { return [] }
    return s.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
}

// --spatial mode: strict vertical focus within a workspace.
// Outputs:
//   a window-id  — vertically-offset target found (vertical split)
//   "cycle"      — windows are stacked (accordion), caller should use aerospace focus
//   (nothing)    — only horizontal neighbors, do nothing
if CommandLine.arguments.count >= 5 && CommandLine.arguments[1] == "--spatial" {
    let dir = CommandLine.arguments[2]
    guard let focusedId = Int(CommandLine.arguments[3]) else { exit(2) }
    let wsIds = Set(readLines(CommandLine.arguments[4]).compactMap(Int.init))
    guard !wsIds.isEmpty else { exit(0) }

    let allIds = wsIds.union([focusedId])
    let frames = cgFrames(for: allIds)
    guard let focusedFrame = frames.first(where: { $0.id == focusedId }) else { exit(0) }

    let others = frames.filter { $0.id != focusedId }
    guard !others.isEmpty else { exit(0) }

    let focusedMidY = focusedFrame.y + focusedFrame.h / 2
    let threshold: CGFloat = 50

    // Check for vertically-offset windows first (true vertical splits)
    let vertical: [Frame]
    switch dir {
    case "down":
        vertical = others.filter { $0.y + $0.h / 2 > focusedMidY + threshold }
    case "up":
        vertical = others.filter { $0.y + $0.h / 2 < focusedMidY - threshold }
    default:
        exit(2)
    }

    if !vertical.isEmpty {
        let pick: Frame?
        switch dir {
        case "down": pick = vertical.min { $0.y < $1.y }
        case "up":   pick = vertical.max { $0.y < $1.y }
        default:     pick = nil
        }
        if let p = pick { print(p.id) }
        exit(0)
    }

    // No vertical target. Check if windows are stacked (accordion) —
    // same position as focused window (within threshold).
    let stacked = others.filter {
        abs($0.x - focusedFrame.x) < threshold && abs($0.y - focusedFrame.y) < threshold
    }
    if !stacked.isEmpty {
        print("cycle")
        exit(0)
    }

    // Only horizontal neighbors remain — do nothing.
    exit(0)
}

// Cross-monitor mode (left/right)
guard CommandLine.arguments.count >= 4 else { exit(2) }
let dir = CommandLine.arguments[1]
let monitorsPath = CommandLine.arguments[2]
let windowsPath = CommandLine.arguments[3]

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

var idx = startIdx
var candidates: [Win] = []
while true {
    switch dir {
    case "right": idx += 1
    case "left":  idx -= 1
    default: break
    }
    guard idx >= 0 && idx < n else { break }
    let mon = monitors[idx]
    guard let visWs = allWindows.first(where: { $0.monitor == mon && $0.wsVisible })?.workspace else { continue }
    let inWs = allWindows.filter { $0.workspace == visWs }
    if !inWs.isEmpty { candidates = inWs; break }
}
guard !candidates.isEmpty else { exit(0) }

let candidateIds = Set(candidates.map(\.id))
let frames = cgFrames(for: candidateIds)
guard !frames.isEmpty else { exit(0) }

// Check if candidates are horizontally spread (different X positions).
// Only then does spatial "leftmost/rightmost" pick make sense.
let xSpread = frames.map(\.x).max()! - frames.map(\.x).min()!

if xSpread > 50 {
    // Horizontal layout — pick the spatial edge window.
    let pick: Frame?
    switch dir {
    case "right": pick = frames.min { $0.x < $1.x }
    case "left":  pick = frames.max { $0.x < $1.x }
    default:      exit(2)
    }
    if let p = pick { print(p.id) }
} else {
    // Vertical split or stacked — let aerospace focus last-focused window.
    let ws = candidates[0].workspace
    print("ws:\(ws)")
}
