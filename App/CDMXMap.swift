import SwiftUI

/// CDMX-flavored street-grid map drawn entirely in SwiftUI Canvas.
/// Mirrors the SVG map.jsx from the design bundle.
struct CDMXMap: View {
    /// Height in design points (402-wide coordinate space)
    var designHeight: CGFloat
    var night: Bool = false
    var routes: [MapRoute] = []
    var markers: [MapMarker] = []
    var heatmap: [HeatmapBlob]? = nil
    var userPos: CGPoint? = nil
    var showLabels: Bool = true

    static let designWidth: CGFloat = 402

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width  / CDMXMap.designWidth
            let sy = size.height / designHeight

            // ── Map palette ──────────────────────────────────
            let paper  = Color(hex: night ? "0E131D" : "EFE9DD")
            let block  = Color(hex: night ? "141B27" : "F7F1E6")
            let park   = Color(hex: night ? "1A2B23" : "D5E4CE")
            let road   = Color(hex: night ? "1E2838" : "FFFCF4")
            let avEdge      = night ? Color.white.opacity(0.08) : Color(hex: "786446").opacity(0.30)
            let labelCol    = night ? Color.white.opacity(0.35) : Color(hex: "3C2D19").opacity(0.55)

            // Shorthand helpers
            func line(from a: CGPoint, to b: CGPoint, color: Color, width: CGFloat) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(color), lineWidth: width)
            }

            let cols: CGFloat = 8, rows: CGFloat = 9
            let cW = size.width  / cols
            let cH = size.height / rows

            // ── Background ──────────────────────────────────
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))

            // ── City blocks ─────────────────────────────────
            for r in 0..<Int(rows) {
                for c in 0..<Int(cols) {
                    guard (r + c * 3) % 7 != 0 else { continue }
                    let rect = CGRect(x: CGFloat(c)*cW+2, y: CGFloat(r)*cH+2,
                                     width: cW-4, height: cH-4)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(block.opacity(0.9)))
                }
            }

            // ── Parks ───────────────────────────────────────
            // Parque México (ellipse)
            let pmCX = cW*2.5, pmCY = cH*5.5, pmRX = cW*1.4, pmRY = cH*1.1
            ctx.fill(Path(ellipseIn: CGRect(x: pmCX-pmRX, y: pmCY-pmRY,
                                            width: pmRX*2, height: pmRY*2)), with: .color(park))
            // Alameda (rect)
            ctx.fill(Path(roundedRect: CGRect(x: cW*5.6, y: cH*2.2, width: cW*1.6, height: cH*1.2),
                          cornerRadius: 4), with: .color(park))

            // ── Street grid ─────────────────────────────────
            let rStroke = night ? Color.white.opacity(0.05) : Color(hex: "786446").opacity(0.18)
            for i in 0...Int(rows) {
                line(from: CGPoint(x: 0, y: CGFloat(i)*cH),
                     to: CGPoint(x: size.width, y: CGFloat(i)*cH), color: rStroke, width: 0.8)
            }
            for i in 0...Int(cols) {
                line(from: CGPoint(x: CGFloat(i)*cW, y: 0),
                     to: CGPoint(x: CGFloat(i)*cW, y: size.height), color: rStroke, width: 0.8)
            }

            // ── Avenidas principales ─────────────────────────
            // Av. Álvaro Obregón (horizontal)
            line(from: CGPoint(x: 0, y: cH*3), to: CGPoint(x: size.width, y: cH*3),
                 color: road, width: 6)
            line(from: CGPoint(x: 0, y: cH*3), to: CGPoint(x: size.width, y: cH*3),
                 color: avEdge, width: 0.6)

            // Av. Cuauhtémoc (vertical)
            line(from: CGPoint(x: cW*5, y: 0), to: CGPoint(x: cW*5, y: size.height),
                 color: road, width: 5)
            line(from: CGPoint(x: cW*5, y: 0), to: CGPoint(x: cW*5, y: size.height),
                 color: avEdge, width: 0.6)

            // Insurgentes (diagonal)
            line(from: CGPoint(x: -20, y: size.height+40), to: CGPoint(x: size.width+20, y: -40),
                 color: road, width: 6)
            line(from: CGPoint(x: -20, y: size.height+40), to: CGPoint(x: size.width+20, y: -40),
                 color: avEdge, width: 0.6)

            // ── Labels ──────────────────────────────────────
            if showLabels {
                func label(_ text: String, x: CGFloat, y: CGFloat, anchor: UnitPoint = .leading) {
                    ctx.draw(
                        Text(text).font(.system(size: 7, weight: .regular)).foregroundStyle(labelCol),
                        at: CGPoint(x: x, y: y), anchor: anchor
                    )
                }
                label("AV. ÁLVARO OBREGÓN", x: 16, y: cH*3 - 7)
                label("PARQUE MÉXICO", x: pmCX, y: pmCY + 4, anchor: .center)
                label("ALAMEDA", x: cW*6.4, y: cH*2.85, anchor: .center)
            }

            // ── Heatmap (blurred blobs) ──────────────────────
            if let blobs = heatmap {
                for blob in blobs {
                    let bx = blob.center.x * sx
                    let by = blob.center.y * sy
                    let br = blob.radius * ((sx + sy) / 2)
                    ctx.drawLayer { lctx in
                        lctx.addFilter(.blur(radius: br * 0.5))
                        lctx.fill(
                            Path(ellipseIn: CGRect(x: bx-br, y: by-br, width: br*2, height: br*2)),
                            with: .color(blob.color.opacity(blob.opacity))
                        )
                    }
                }
            }

            // ── Routes ──────────────────────────────────────
            for route in routes {
                var path = Path()
                for (i, dp) in route.points.enumerated() {
                    let sp = CGPoint(x: dp.x * sx, y: dp.y * sy)
                    if i == 0 { path.move(to: sp) } else { path.addLine(to: sp) }
                }
                let cap: CGLineCap = .round
                let join: CGLineJoin = .round
                if route.isActive {
                    ctx.stroke(path, with: .color(route.color.opacity(0.22)),
                               style: StrokeStyle(lineWidth: 12, lineCap: cap, lineJoin: join))
                }
                ctx.stroke(path,
                           with: .color(route.isActive ? route.color : route.color.opacity(0.55)),
                           style: StrokeStyle(lineWidth: route.isActive ? 5 : 3.5,
                                             lineCap: cap, lineJoin: join,
                                             dash: route.isDashed ? [2, 5] : []))
            }

            // ── Markers ─────────────────────────────────────
            for marker in markers {
                let mx = marker.point.x * sx
                let my = marker.point.y * sy
                switch marker.kind {
                case .origin:
                    ctx.fill(Path(ellipseIn: CGRect(x: mx-7, y: my-7, width: 14, height: 14)),
                             with: .color(T.ink))
                    ctx.fill(Path(ellipseIn: CGRect(x: mx-3, y: my-3, width: 6, height: 6)),
                             with: .color(T.cream))
                case .dest:
                    var d = Path()
                    d.move(to: CGPoint(x: mx, y: my-20))
                    d.addLine(to: CGPoint(x: mx+5, y: my-10))
                    d.addLine(to: CGPoint(x: mx, y: my))
                    d.addLine(to: CGPoint(x: mx-5, y: my-10))
                    d.closeSubpath()
                    ctx.fill(d, with: .color(T.accent))
                    ctx.fill(Path(ellipseIn: CGRect(x: mx-3.5, y: my-15.5, width: 7, height: 7)),
                             with: .color(T.paper))
                }
            }

            // ── User position ───────────────────────────────
            if let pos = userPos {
                let ux = pos.x * sx, uy = pos.y * sy
                let blue = Color(hex: "2563EB")
                ctx.fill(Path(ellipseIn: CGRect(x: ux-16, y: uy-16, width: 32, height: 32)),
                         with: .color(blue.opacity(0.15)))
                ctx.fill(Path(ellipseIn: CGRect(x: ux-10, y: uy-10, width: 20, height: 20)),
                         with: .color(blue.opacity(0.25)))
                ctx.fill(Path(ellipseIn: CGRect(x: ux-6,  y: uy-6,  width: 12, height: 12)),
                         with: .color(blue))
                ctx.stroke(Path(ellipseIn: CGRect(x: ux-6, y: uy-6, width: 12, height: 12)),
                           with: .color(.white), lineWidth: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: designHeight)
    }
}

