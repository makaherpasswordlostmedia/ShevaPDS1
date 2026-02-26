// CrtView.swift — Phosphor CRT renderer using Metal for iOS
// Ported from CrtView.java (Android Canvas → Metal/Core Graphics)

import UIKit
import Metal
import MetalKit

final class CrtView: UIView {

    private static let PDS = 1024

    // Phosphor layer colors
    private let colorCore  = UIColor(red:20/255, green:1.0,    blue:65/255,  alpha:1.0)
    private let colorMid   = UIColor(red:0,      green:200/255,blue:50/255,  alpha:0.43)
    private let colorOuter = UIColor(red:0,      green:140/255,blue:35/255,  alpha:0.14)
    private let colorDecay = UIColor(red:0,       green:0,      blue:0,       alpha:0.15)

    // State
    var machine: Machine?
    var demos: Demos?
    private(set) var actualFps: Float = 0
    var maxFps: Int = 30

    // Offscreen bitmap
    private var offBitmap: UIImage?
    private var offContext: CGContext?
    private var offSize = CGSize.zero

    // Render loop
    private var displayLink: CADisplayLink?
    private var fpsTime: CFTimeInterval = 0
    private var fpsCnt: Int = 0
    private var lastFrame: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentMode = .redraw
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != offSize { recreateBitmap() }
    }

    func start() {
        stop()
        recreateBitmap()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink!.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func recreateBitmap() {
        let sz = bounds.size
        guard sz.width > 0 && sz.height > 0 else { return }
        offSize = sz
        let scale = UIScreen.main.scale
        let w = Int(sz.width * scale), h = Int(sz.height * scale)
        guard w > 0 && h > 0 else { return }
        let cs = CGColorSpaceCreateDeviceRGB()
        offContext = CGContext(data: nil, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: w*4,
                              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        offContext?.setFillColor(UIColor.black.cgColor)
        offContext?.fill(CGRect(x:0,y:0,width:w,height:h))
    }

    @objc private func tick(_ link: CADisplayLink) {
        // FPS cap
        let now = link.timestamp
        let frameDur = 1.0 / Double(maxFps)
        if now - lastFrame < frameDur * 0.95 { return }
        lastFrame = now

        // Update
        let m = machine, d = demos
        guard let m, let d, let ctx = offContext else { return }
        m.dlClear()
        d.runCurrentDemo()
        renderFrame(m, ctx)

        // Convert to UIImage and display
        if let cgImg = ctx.makeImage() {
            offBitmap = UIImage(cgImage: cgImg, scale: UIScreen.main.scale, orientation: .up)
        }
        DispatchQueue.main.async { self.setNeedsDisplay() }

        // FPS counter
        fpsCnt += 1
        if now - fpsTime >= 1.0 { actualFps = Float(fpsCnt); fpsCnt = 0; fpsTime = now }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        // Draw offscreen bitmap
        if let img = offBitmap {
            img.draw(in: bounds)
        }
        // Scanlines overlay
        let h = bounds.height
        ctx.setLineWidth(1.0)
        ctx.setStrokeColor(UIColor(white: 0, alpha: 0.07).cgColor)
        var y: CGFloat = 0
        while y < h { ctx.move(to: CGPoint(x:0,y:y)); ctx.addLine(to: CGPoint(x:bounds.width,y:y)); y += 3 }
        ctx.strokePath()
        // Vignette
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(bounds.width, bounds.height) * 0.65
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor.clear.cgColor, UIColor(white:0,alpha:0.6).cgColor] as CFArray,
                                  locations: [0, 1]) {
            ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: radius, options: [])
        }
    }

    private func renderFrame(_ m: Machine, _ ctx: CGContext) {
        let sw = offSize.width * UIScreen.main.scale
        let sh = offSize.height * UIScreen.main.scale
        let sx = sw / CGFloat(CrtView.PDS)
        let sy = sh / CGFloat(CrtView.PDS)

        // Phosphor decay
        ctx.setFillColor(colorDecay.cgColor)
        ctx.fill(CGRect(x:0,y:0,width:sw,height:sh))

        ctx.setLineCap(.round)

        let nv = m.nvec
        for i in 0..<nv {
            let v = m.vecs[i]
            let b = v.bright
            if b < 0.04 { continue }

            let x1 = CGFloat(v.x1) * sx
            let y1 = sh - CGFloat(v.y1) * sy

            if v.isPoint {
                // Outer glow
                ctx.setFillColor(UIColor(red:0, green:140/255, blue:35/255, alpha:CGFloat(b)*0.12).cgColor)
                ctx.fillEllipse(in: CGRect(x:x1-5,y:y1-5,width:10,height:10))
                // Mid
                ctx.setFillColor(UIColor(red:0, green:200/255, blue:50/255, alpha:CGFloat(b)*0.35).cgColor)
                ctx.fillEllipse(in: CGRect(x:x1-2.5,y:y1-2.5,width:5,height:5))
                // Core
                ctx.setFillColor(UIColor(red:20/255, green:1.0, blue:65/255, alpha:CGFloat(b)).cgColor)
                ctx.fillEllipse(in: CGRect(x:x1-1.2,y:y1-1.2,width:2.4,height:2.4))
            } else {
                let x2 = CGFloat(v.x2) * sx
                let y2 = sh - CGFloat(v.y2) * sy
                // Outer glow
                ctx.setStrokeColor(UIColor(red:0, green:140/255, blue:35/255, alpha:CGFloat(b)*0.12).cgColor)
                ctx.setLineWidth(8)
                ctx.move(to: CGPoint(x:x1,y:y1)); ctx.addLine(to: CGPoint(x:x2,y:y2)); ctx.strokePath()
                // Mid
                ctx.setStrokeColor(UIColor(red:0, green:200/255, blue:50/255, alpha:CGFloat(b)*0.38).cgColor)
                ctx.setLineWidth(3.5)
                ctx.move(to: CGPoint(x:x1,y:y1)); ctx.addLine(to: CGPoint(x:x2,y:y2)); ctx.strokePath()
                // Core
                ctx.setStrokeColor(UIColor(red:20/255, green:1.0, blue:65/255, alpha:CGFloat(b)).cgColor)
                ctx.setLineWidth(1.3)
                ctx.move(to: CGPoint(x:x1,y:y1)); ctx.addLine(to: CGPoint(x:x2,y:y2)); ctx.strokePath()
            }
        }
    }

    func screenToPDS(_ pt: CGPoint) -> (x: Int, y: Int) {
        return (Int(pt.x / bounds.width * CGFloat(CrtView.PDS)),
                Int((1 - pt.y / bounds.height) * CGFloat(CrtView.PDS)))
    }
}
