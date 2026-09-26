import CoreGraphics
import Foundation
import ShiftZonesCore

// Checks for the core logic. Run with `swift run CoreChecks`.

var failures = 0

func check(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String, line: Int = #line) {
    if !condition() {
        failures += 1
        print("✗ line \(line): \(message())")
    }
}

func approx(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) < tolerance }

// MARK: Templates cover the whole area without overlapping

for template in LayoutTemplate.allCases {
    for count in 1...12 {
        let zones = template.zones(count: count)
        let label = "\(template.rawValue)(\(count))"
        check(zones.count == count, "\(label): \(zones.count) zones")
        check(approx(zones.reduce(0) { $0 + $1.rect.area }, 1), "\(label): total area is not 1")
        check(zones.allSatisfy { $0.rect.minX >= 0 && $0.rect.minY >= 0 && $0.rect.maxX <= 1 + 1e-12 && $0.rect.maxY <= 1 + 1e-12 },
              "\(label): zone outside the area")
        for (i, a) in zones.enumerated() {
            for b in zones[(i + 1)...] { check(!a.rect.overlaps(b.rect), "\(label): overlapping zones") }
        }
    }
}

let grid3 = LayoutTemplate.grid.zones(count: 3)
check(approx(grid3[0].rect.height, 1) && approx(grid3[1].rect.height, 0.5), "grid of 3: one full-height zone on the left, two on the right")
let priority3 = LayoutTemplate.priorityGrid.zones(count: 3)
check(approx(priority3[1].rect.x, 0.25) && approx(priority3[1].rect.width, 0.5), "priority of 3: center zone half as wide")

// MARK: Geometry

let area = CGRect(x: 100, y: 25, width: 1000, height: 500)
let columns2 = LayoutTemplate.columns.zones(count: 2)
let left = ZoneGeometry.windowFrame(of: columns2[0].rect, in: area, spacing: 10)
let right = ZoneGeometry.windowFrame(of: columns2[1].rect, in: area, spacing: 10)
check(left == CGRect(x: 110, y: 35, width: 485, height: 480), "left frame \(left)")
check(right.minX - left.maxX == 10, "gap between zones \(right.minX - left.maxX)")
check(area.maxX - right.maxX == 10 && area.maxY - right.maxY == 10, "outer margin")
check(ZoneGeometry.windowFrame(of: .full, in: area, spacing: 0) == area, "spacing 0 = whole area")

let grid4 = LayoutTemplate.grid.zones(count: 4)
check(ZoneGeometry.zone(at: CGPoint(x: 850, y: 425), in: grid4, area: area)?.id == grid4[3].id, "zone under the cursor (bottom right)")
check(ZoneGeometry.zone(at: CGPoint(x: 50, y: 50), in: grid4, area: area) == nil, "cursor outside the area")
let big = Zone(rect: .full), small = Zone(rect: ZoneRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
check(ZoneGeometry.zone(at: CGPoint(x: 600, y: 275), in: [big, small], area: area)?.id == small.id, "overlapping: the smallest wins")

// MARK: Combining zones

let priority5 = LayoutTemplate.priorityGrid.zones(count: 5)   // top-left, bottom-left, center, top-right, bottom-right
let spanned = ZoneGeometry.span(from: priority5[0], to: priority5[2], in: priority5)
check(Set(spanned.map(\.id)) == Set(priority5[0...2].map(\.id)), "top-left → center also includes bottom-left")
check(ZoneGeometry.boundingRect(of: spanned) == .edges(minX: 0, minY: 0, maxX: 0.75, maxY: 1), "bounding rectangle")
check(ZoneGeometry.span(from: priority5[3], to: priority5[3], in: priority5).map(\.id) == [priority5[3].id], "single zone")

// MARK: Editor: moving with snapping

let pair = [Zone(rect: ZoneRect(x: 0, y: 0, width: 0.5, height: 1)),
            Zone(rect: ZoneRect(x: 0.6, y: 0.2, width: 0.3, height: 0.3))]
let snapped = ZoneEditing.move(pair[1].id, in: pair, dx: -0.095, dy: 0, threshold: (0.01, 0.01))
check(approx(snapped[1].rect.x, 0.5), "snaps to the neighbor's edge: \(snapped[1].rect.x)")
let free = ZoneEditing.move(pair[1].id, in: pair, dx: -0.095, dy: 0, threshold: (0, 0))
check(approx(free[1].rect.x, 0.505), "without snapping: \(free[1].rect.x)")
let clamped = ZoneEditing.move(pair[1].id, in: pair, dx: 5, dy: -5, threshold: (0, 0))
check(approx(clamped[1].rect.maxX, 1) && approx(clamped[1].rect.y, 0), "stays inside the area")
check(clamped[0] == pair[0], "other zones don't change")

// MARK: Editor: resizing with linked edges

let columns3 = LayoutTemplate.columns.zones(count: 3)
let min5 = (width: 0.05, height: 0.05)
let linked = ZoneEditing.resize(columns3[0].id, in: columns3, edges: .right, dx: 0.1, dy: 0, linked: true, threshold: (0, 0), minSize: min5)
check(approx(linked[0].rect.maxX, 1.0 / 3 + 0.1) && approx(linked[1].rect.minX, 1.0 / 3 + 0.1), "the shared edge moves for both zones")
check(approx(linked[1].rect.maxX, 2.0 / 3) && linked[2] == columns3[2], "other zones stay put")
let unlinked = ZoneEditing.resize(columns3[0].id, in: columns3, edges: .right, dx: 0.1, dy: 0, linked: false, threshold: (0, 0), minSize: min5)
check(unlinked[1] == columns3[1], "⌥: only the dragged zone")
let limited = ZoneEditing.resize(columns3[0].id, in: columns3, edges: .right, dx: 0.9, dy: 0, linked: true, threshold: (0, 0), minSize: min5)
check(approx(limited[0].rect.maxX, 2.0 / 3 - 0.05), "respects the neighbor's minimum size: \(limited[0].rect.maxX)")
let border = ZoneEditing.resize(columns3[0].id, in: columns3, edges: .left, dx: 0.1, dy: 0, linked: true, threshold: (0, 0), minSize: min5)
check(approx(border[0].rect.minX, 0.1) && border[1] == columns3[1], "the screen edge is not linked")
let corner = ZoneEditing.resize(columns3[1].id, in: columns3, edges: [.right, .bottom], dx: 0.02, dy: -0.47, linked: true, threshold: (0.05, 0.05), minSize: min5)
check(approx(corner[1].rect.maxX, 2.0 / 3 + 0.02) && approx(corner[2].rect.minX, 2.0 / 3 + 0.02), "corner: right edge linked")
check(approx(corner[1].rect.maxY, 0.5) && approx(corner[2].rect.maxY, 1), "corner: snaps at half height, bottom edge not linked")

// MARK: Editor: splitting

let halves = ZoneEditing.split(Zone(rect: .full), .columns)
check(halves.count == 2 && approx(halves[0].rect.width, 0.5) && approx(halves[1].rect.x, 0.5), "split into columns")
let stacked = ZoneEditing.split(Zone(rect: .full), .rows)
check(approx(stacked[1].rect.y, 0.5) && approx(stacked[1].rect.height, 0.5), "split into rows")

// MARK: Zones file: parsing

let wide = MonitorDescriptor(id: "WIDE", name: "ZQE-CBA", resolution: "3440 × 1440", isPrimary: true, aspectRatio: 3440.0 / 1415)
let laptop = MonitorDescriptor(id: "LAPTOP", name: "Built-in Retina Display", resolution: "1512 × 982", aspectRatio: 1512.0 / 949)
let superWide = MonitorDescriptor(id: "SUPER", name: "PHL 499P9", resolution: "5120 × 1440", aspectRatio: 5120.0 / 1415)

func rects(_ zones: [Zone]) -> [[Double]] {
    zones.map { [$0.rect.x, $0.rect.y, $0.rect.width, $0.rect.height].map { ($0 * 10_000).rounded() / 10_000 } }
}

let sample = """
# comment
[ZQE-CBA · 3440 × 1440 · primary]
id = WIDE
  0   0  30%  100     # left column
 30   0  40   100
 70   0  30    50
 70  50  30,0  50

[Built-in Retina Display]
0 0 100 100
"""
switch ZoneFile.parse(sample, connected: [wide, laptop]) {
case .success(let content):
    check(content.monitors.map(\.id) == ["WIDE", "LAPTOP"], "ids read and matched by name: \(content.monitors.map(\.id))")
    check(rects(content.monitors[0].zones) == [[0, 0, 0.3, 1], [0.3, 0, 0.4, 1], [0.7, 0, 0.3, 0.5], [0.7, 0.5, 0.3, 0.5]],
          "percentages → fractions: \(rects(content.monitors[0].zones))")
    check(content.monitors[0].resolution == "3440 × 1440", "resolution from the header")
    check(content.listedAsConnected == ["WIDE", "LAPTOP"], "both listed as connected")
case .failure(let error):
    check(false, "sample file is invalid: line \(error.line) \(error.message)")
}

func expectError(_ text: String, line: Int, containing fragment: String, _ caller: Int = #line) {
    switch ZoneFile.parse(text, connected: [wide]) {
    case .success:
        check(false, "expected an error at line \(line)", line: caller)
    case .failure(let error):
        check(error.line == line && error.message.contains(fragment), "error: line \(error.line) \"\(error.message)\"", line: caller)
    }
}
expectError("0 0 50 100", line: 1, containing: "header")
expectError("[A]\nid = WIDE\n0 0 50", line: 3, containing: "4 numbers")
expectError("[A]\nid = WIDE\n60 0 50 100", line: 3, containing: "right edge")
expectError("[A]\nid = WIDE\n0 20 50 90", line: 3, containing: "bottom edge")
expectError("[A]\nid = WIDE\n0 0 fifty 100", line: 3, containing: "not a number")
expectError("[A]\nid = WIDE\n0 0 0 100", line: 3, containing: "greater than 0")
expectError("[A]\nname = x", line: 2, containing: "unknown setting")
expectError("[Unknown]\n0 0 50 100", line: 1, containing: "id")
expectError("[A]\nid = WIDE\n\n[B]\nid = WIDE", line: 4, containing: "line 1")
expectError("[A\nid = WIDE", line: 1, containing: "]")

if case .success(let content) = ZoneFile.parse("[A]\nid = WIDE\n", connected: []) {
    check(content.monitors[0].zones.isEmpty, "display without lines = no zones")
}
let withDisconnected = "[A]\nid = WIDE\n0 0 100 100\n\n# ─── Disconnected displays ───\n[B]\nid = OLD\n0 0 50 100\n"
if case .success(let content) = ZoneFile.parse(withDisconnected, connected: [wide]) {
    check(content.listedAsConnected == ["WIDE"] && content.monitors.count == 2, "disconnected displays section")
} else {
    check(false, "file with disconnected displays is invalid")
}

// MARK: Zones file: writing

let thirds = LayoutTemplate.columns.zones(count: 3)
let rendered = ZoneFile.render(connected: [MonitorZones(id: "WIDE", name: "ZQE-CBA", resolution: "3440 × 1440", zones: thirds)],
                               primaryID: "WIDE",
                               disconnected: [MonitorZones(id: "OLD", name: "Old", resolution: nil, zones: [])])
check(rendered.contains("[ZQE-CBA · 3440 × 1440 · primary]\nid = WIDE"), "header and id")
check(rendered.contains("\n  33.33      0  33.34    100\n"), "rounded edges, zones stay flush:\n\(rendered)")
if case .success(let content) = ZoneFile.parse(rendered, connected: []) {
    let back = content.monitors[0].zones
    check(zip(back, thirds).allSatisfy { abs($0.rect.minX - $1.rect.minX) < 1e-4 && abs($0.rect.maxX - $1.rect.maxX) < 1e-4 },
          "round trip")
    check(content.listedAsConnected == ["WIDE"] && content.monitors[1].zones.isEmpty, "disconnected display without zones")
} else {
    check(false, "the generated file can't be read back")
}

// MARK: Zones file: regeneration

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shiftzones-check-\(UUID().uuidString)")
let zonesURL = directory.appendingPathComponent("zones.conf")
func fileText() -> String { (try? String(contentsOf: zonesURL, encoding: .utf8)) ?? "" }
func position(_ fragment: String) -> String.Index? { fileText().range(of: fragment)?.lowerBound }

let store = LayoutStore(fileURL: zonesURL)
store.update(connected: [wide])
check(fileText().contains("id = WIDE"), "first launch: file created")
check(store.layout(forDisplay: "WIDE", aspectRatio: 1).zones.count == 3, "ultrawide: 3 default zones")

let edited = "[ZQE-CBA]\nid = WIDE\n0 0 50 100\n50 0 50 100  # my comment\n"
try! edited.write(to: zonesURL, atomically: true, encoding: .utf8)
check(store.reload(), "manual edit detected")
check(rects(store.layout(forDisplay: "WIDE", aspectRatio: 1).zones) == [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]], "hand-edited zones active")
check(!store.reload(), "unchanged file: no reload")

LayoutStore(fileURL: zonesURL).update(connected: [wide])
check(fileText() == edited, "relaunch with the same displays: file left as is")

store.update(connected: [laptop, wide])
check(fileText().contains("id = LAPTOP") && !fileText().contains("my comment"), "display connected: file regenerated")
check(rects(store.layout(forDisplay: "WIDE", aspectRatio: 1).zones) == [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]], "edited zones kept")
check(store.layout(forDisplay: "LAPTOP", aspectRatio: 1).zones.count == 2, "new display: default zones")
check(position("id = LAPTOP")! < position("id = WIDE")!, "displays ordered left to right")

let beforeReconfiguration = fileText()
store.update(connected: [])
check(fileText() == beforeReconfiguration, "no displays reported (reconfiguration): file left as is")

store.update(connected: [wide])
check(position("Disconnected displays")! < position("id = LAPTOP")!, "display disconnected: moved to the bottom")
store.update(connected: [laptop, wide])
check(!fileText().contains("Disconnected displays"), "display reconnected: back among the connected ones")

let broken = fileText().replacingOccurrences(of: "id = LAPTOP\n", with: "id = LAPTOP\n1 2 3\n")
try! broken.write(to: zonesURL, atomically: true, encoding: .utf8)
check(store.reload() && store.error?.message.contains("4 numbers") == true, "error detected: \(String(describing: store.error))")
check(store.layout(forDisplay: "WIDE", aspectRatio: 1).zones.count == 2, "with errors the last valid zones stay active")
let restarted = LayoutStore(fileURL: zonesURL)
restarted.update(connected: [laptop, wide])
check(fileText() == broken && restarted.error != nil, "at launch a file with errors is not rewritten")

store.update(connected: [laptop, wide, superWide])
check(store.error == nil && fileText().contains("id = SUPER"), "file with errors + new display: regenerated")
check((try? String(contentsOf: store.backupURL, encoding: .utf8)) == broken, "backup of the file with errors")
check(fileText().contains("zones.conf.bak"), "note about the backup in the file")
check(rects(store.layout(forDisplay: "WIDE", aspectRatio: 1).zones) == [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]], "valid zones kept")

try? FileManager.default.removeItem(at: zonesURL)
check(store.reload() && fileText().contains("id = SUPER"), "file deleted: recreated")

store.setLayout(ZoneLayout(zones: LayoutTemplate.columns.zones(count: 4)), forDisplay: "SUPER", name: "PHL 499P9")
let reread = LayoutStore(fileURL: zonesURL)
reread.update(connected: [laptop, wide, superWide])
check(reread.layout(forDisplay: "SUPER", aspectRatio: 1).zones.count == 4, "editor save written to the file")
try? FileManager.default.removeItem(at: directory)

print(failures == 0 ? "✓ all checks passed" : "✗ \(failures) checks failed")
exit(failures == 0 ? 0 : 1)
