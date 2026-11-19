import UIKit
import CoreGraphics
import CoreText
import CoreLocation
import ImageIO

/// Menggambar satu frame dash (480×234) di CPU menjadi JPEG, untuk 3 tampilan:
/// Peta+Data, Speedometer, dan Musik. Nama jalan & rambu kecepatan juga dikirim terpisah
/// ke dash (cmd 3 & 17), jadi tidak wajib digambar di sini.
struct DashRenderer {
    let width: Int
    let height: Int

    init(width: Int = 480, height: Int = 234) {
        self.width = width
        self.height = height
    }

    // Warna
    private let teal = UIColor(red: 0.18, green: 0.88, blue: 0.78, alpha: 1)
    private let green = UIColor(red: 0.04, green: 0.54, blue: 0.36, alpha: 1)
    private let panelBg = UIColor(red: 0.13, green: 0.08, blue: 0.10, alpha: 1)
    private let cardA = UIColor(red: 0.63, green: 0.35, blue: 0.43, alpha: 1)
    private let cardB = UIColor(red: 0.36, green: 0.19, blue: 0.25, alpha: 1)
    private let ink = UIColor.white
    private let muted = UIColor(white: 0.72, alpha: 1)

    // MARK: - Entry

    func render(view: DashView,
                speedKmh: Int,
                limitKmh: Int,
                fuelPercent: Double,
                slots: [(String, String)],
                route: [CLLocationCoordinate2D],
                center: CLLocationCoordinate2D,
                music: NowPlaying) -> Data? {
        switch view {
        case .map: return renderMap(route: route, center: center, speedKmh: speedKmh, fuelPercent: fuelPercent, slots: slots)
        case .speedo: return renderSpeedo(speedKmh: speedKmh, limitKmh: limitKmh, fuelPercent: fuelPercent)
        case .music: return renderMusic(music)
        }
    }

    // MARK: - Peta + Data

    private func renderMap(route: [CLLocationCoordinate2D], center: CLLocationCoordinate2D,
                           speedKmh: Int, fuelPercent: Double, slots: [(String, String)]) -> Data? {
        guard let ctx = newContext() else { return nil }
        let w = Double(width), h = Double(height)
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let cosLat = cos(center.latitude * .pi / 180)
        func proj(_ c: CLLocationCoordinate2D) -> CGPoint {
            let dx = (c.longitude - center.longitude) * 111_320 * cosLat
            let dy = (c.latitude - center.latitude) * 110_540
            return CGPoint(x: w / 2 + CGFloat(dx / 4), y: h / 2 + CGFloat(dy / 4))
        }

        if route.count > 1 {
            ctx.setStrokeColor(teal.cgColor)
            ctx.setLineWidth(10); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            for i in 1..<route.count {
                ctx.move(to: proj(route[i - 1]))
                ctx.addLine(to: proj(route[i]))
            }
            ctx.strokePath()
        }

        // Posisi (segitiga)
        let p = CGPoint(x: w / 2, y: h / 2)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.move(to: CGPoint(x: p.x, y: p.y + 16))
        ctx.addLine(to: CGPoint(x: p.x - 12, y: p.y - 12))
        ctx.addLine(to: CGPoint(x: p.x + 12, y: p.y - 12))
        ctx.closePath()
        ctx.fillPath()

        // Kecepatan (kiri)
        drawText("\(speedKmh)", at: CGPoint(x: 72, y: 62), size: 60, color: UIColor.white.cgColor, context: ctx)

        // Panel data kanan
        drawDataPanel(ctx, slots: slots)

        return finish(ctx)
    }

    private func drawDataPanel(_ ctx: CGContext, slots: [(String, String)]) {
        // Kartu besar (nama + cuaca + ODO)
        fillRounded(CGRect(x: 330, y: 8, width: 144, height: 74), radius: 10, color: cardA, context: ctx, border: UIColor(white: 1, alpha: 0.35))
        drawText("Tantan", at: CGPoint(x: 340, y: 30), size: 16, color: ink.cgColor, context: ctx)
        drawText("25° Berawan", at: CGPoint(x: 340, y: 52), size: 12, color: UIColor(white: 1, alpha: 0.9).cgColor, context: ctx)
        drawText("ODO 28181 km", at: CGPoint(x: 340, y: 72), size: 10, color: UIColor(white: 1, alpha: 0.8).cgColor, context: ctx)

        // 4 kartu kecil (dari slot yang dipilih)
        let items: [(String, String)] = slots.count >= 4
            ? Array(slots.prefix(4))
            : slots + Array(repeating: ("", ""), count: 4 - slots.count)
        let xs = [330.0, 404.0]
        let ys = [86.0, 132.0]
        var idx = 0
        for y in ys {
            for x in xs {
                fillRounded(CGRect(x: x, y: y, width: 70, height: 42), radius: 10, color: panelBg, context: ctx, border: UIColor(red: 0.56, green: 0.35, blue: 0.43, alpha: 1))
                let (k, v) = items[idx]
                drawText(k, at: CGPoint(x: x + 6, y: y + 14), size: 9, color: UIColor(white: 1, alpha: 0.85).cgColor, context: ctx)
                drawText(v, at: CGPoint(x: x + 6, y: y + 34), size: 18, color: ink.cgColor, context: ctx)
                idx += 1
            }
        }
    }

    // MARK: - Speedometer

    private func renderSpeedo(speedKmh: Int, limitKmh: Int, fuelPercent: Double) -> Data? {
        guard let ctx = newContext() else { return nil }
        let w = Double(width), h = Double(height)
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Angka kecepatan besar
        drawText("\(speedKmh)", at: CGPoint(x: 150, y: 130), size: 120, color: ink.cgColor, context: ctx)
        drawText("km/jam", at: CGPoint(x: 156, y: 100), size: 18, color: muted.cgColor, context: ctx)

        // Rambu batas kecepatan (kanan atas)
        let signCenter = CGPoint(x: 420, y: 180)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.setStrokeColor(UIColor(red: 0.88, green: 0.13, blue: 0.11, alpha: 1).cgColor)
        ctx.setLineWidth(6)
        ctx.strokeEllipse(in: CGRect(x: signCenter.x - 24, y: signCenter.y - 24, width: 48, height: 48))
        ctx.fillEllipse(in: CGRect(x: signCenter.x - 21, y: signCenter.y - 21, width: 42, height: 42))
        drawText("\(limitKmh)", at: CGPoint(x: signCenter.x - 14, y: signCenter.y - 8), size: 20, color: UIColor.black.cgColor, context: ctx)

        // Bar bensin bawah
        let barW = 200.0, barH = 10.0, barX = 72.0, barY = 30.0
        fillRounded(CGRect(x: barX, y: barY, width: barW, height: barH), radius: 5, color: UIColor(white: 0.2, alpha: 1), context: ctx)
        fillRounded(CGRect(x: barX, y: barY, width: barW * CGFloat(fuelPercent / 100), height: barH), radius: 5, color: teal, context: ctx)
        drawText("Bensin \(Int(fuelPercent))%", at: CGPoint(x: barX, y: barY + 18), size: 14, color: muted.cgColor, context: ctx)

        return finish(ctx)
    }

    // MARK: - Musik

    private func renderMusic(_ music: NowPlaying) -> Data? {
        guard let ctx = newContext() else { return nil }
        let w = Double(width), h = Double(height)
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Sampul album
        let artRect = CGRect(x: 72, y: 40, width: 128, height: 128)
        fillRounded(artRect, radius: 14, color: panelBg, context: ctx)
        drawSymbol("music.note", at: CGPoint(x: 136, y: 104), size: 56, color: muted, context: ctx)

        // Judul & artis
        drawText(music.title, at: CGPoint(x: 216, y: 80), size: 24, color: ink.cgColor, context: ctx)
        drawText(music.artist, at: CGPoint(x: 216, y: 104), size: 18, color: muted.cgColor, context: ctx)

        // Progres
        let barX = 216.0, barY = 120.0, barW = 240.0
        fillRounded(CGRect(x: barX, y: barY, width: barW, height: 6), radius: 3, color: UIColor(white: 0.2, alpha: 1), context: ctx)
        fillRounded(CGRect(x: barX, y: barY, width: barW * 0.4, height: 6), radius: 3, color: teal, context: ctx)

        // Kontrol: prev, play/pause, next
        let cy = 156.0
        drawSymbol("backward.fill", at: CGPoint(x: 240, y: cy), size: 24, color: ink, context: ctx)
        drawSymbol(music.isPlaying ? "pause.fill" : "play.fill", at: CGPoint(x: 290, y: cy), size: 28, color: ink, context: ctx)
        drawSymbol("forward.fill", at: CGPoint(x: 340, y: cy), size: 24, color: ink, context: ctx)

        return finish(ctx)
    }

    // MARK: - Helpers

    private func newContext() -> CGContext? {
        let cs = CGColorSpaceCreateDeviceRGB()
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                         bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }

    private func finish(_ ctx: CGContext) -> Data? {
        guard let img = ctx.makeImage() else { return nil }
        return encodeJPEG(img)
    }

    private func fillRounded(_ rect: CGRect, radius: CGFloat, color: UIColor, context: CGContext, border: UIColor? = nil) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
        if let border = border {
            context.addPath(path)
            context.setStrokeColor(border.cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }
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

    private func drawSymbol(_ name: String, at center: CGPoint, size: CGFloat, color: UIColor, context: CGContext) {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .bold)
        guard let img = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal),
              let cg = img.cgImage else { return }
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        context.draw(cg, in: rect)
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