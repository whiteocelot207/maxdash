import UIKit
import CoreGraphics
import CoreText
import CoreLocation
import ImageIO

/// Menggambar satu frame dash (480×234) di CPU menjadi JPEG.
/// Fokus Milestone 1: garis rute + posisi + angka kecepatan. Nama jalan & rambu batas kecepatan
/// ditangani dash sendiri (cmd 3 & 17), jadi tidak perlu digambar di sini.
struct DashRenderer {
    let width: Int
    let height: Int

    init(width: Int = 480, height: Int = 234) {
        self.width = width
        self.height = height
    }

    func render(passed: [CLLocationCoordinate2D],
                ahead: [CLLocationCoordinate2D],
                center: CLLocationCoordinate2D,
                metersPerPixel: Double = 4,
                speedKmh: Int) -> Data? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let w = Double(width), h = Double(height)

        // Sistem koordinat: origin kiri-bawah, y ke atas (default CGContext).
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let cosLat = cos(center.latitude * .pi / 180)
        func proj(_ c: CLLocationCoordinate2D) -> CGPoint {
            let dx = (c.longitude - center.longitude) * 111_320 * cosLat
            let dy = (c.latitude - center.latitude) * 110_540
            return CGPoint(x: w / 2 + CGFloat(dx / metersPerPixel),
                           y: h / 2 + CGFloat(dy / metersPerPixel))
        }

        // Bagian yang sudah dilewati (abu-abu).
        if passed.count > 1 {
            ctx.setStrokeColor(UIColor(white: 0.35, alpha: 1).cgColor)
            ctx.setLineWidth(10); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            for i in 1..<passed.count {
                ctx.move(to: proj(passed[i - 1]))
                ctx.addLine(to: proj(passed[i]))
            }
            ctx.strokePath()
        }

        // Rute ke depan (teal).
        if ahead.count > 1 {
            ctx.setStrokeColor(UIColor(red: 0.18, green: 0.88, blue: 0.78, alpha: 1).cgColor)
            ctx.setLineWidth(10); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            for i in 1..<ahead.count {
                ctx.move(to: proj(ahead[i - 1]))
                ctx.addLine(to: proj(ahead[i]))
            }
            ctx.strokePath()
        }

        // Segitiga posisi (putih, menghadap ke atas).
        let p = CGPoint(x: w / 2, y: h / 2)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: p.x, y: p.y + 16))
        ctx.addLine(to: CGPoint(x: p.x - 12, y: p.y - 12))
        ctx.addLine(to: CGPoint(x: p.x + 12, y: p.y - 12))
        ctx.closePath()
        ctx.drawPath(using: .fillStroke)

        // Angka kecepatan besar (kiri, di atas road bar).
        drawText("\(speedKmh)", at: CGPoint(x: 72, y: 60), size: 64,
                 color: UIColor.white.cgColor, context: ctx)

        guard let img = ctx.makeImage() else { return nil }
        return encodeJPEG(img)
    }

    private func drawText(_ s: String, at pt: CGPoint, size: CGFloat, color: CGColor, context: CGContext) {
        guard let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) else { return }
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        guard let attr = CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary) else { return }
        let line = CTLineCreateWithAttributedString(attr)
        context.saveGState()
        context.textPosition = pt
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func encodeJPEG(_ image: CGImage, quality: CGFloat = 0.5) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}