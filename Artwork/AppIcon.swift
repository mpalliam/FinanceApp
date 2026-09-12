import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
// Opaque context: no alpha channel at all, which is what Apple requires.
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}
let ink   = rgb(14, 91, 61)
let inkDk = rgb(9, 66, 44)
let paper = rgb(252, 251, 247)
let line  = rgb(203, 212, 206)
let W = CGFloat(S)

ctx.setFillColor(ink)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: W))

let pw: CGFloat = 560, ph: CGFloat = 660
let page = CGRect(x: (W-pw)/2, y: (W-ph)/2, width: pw, height: ph)
let pagePath = CGPath(roundedRect: page, cornerWidth: 34, cornerHeight: 34, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26,
              color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.30))
ctx.setFillColor(paper)
ctx.addPath(pagePath)
ctx.fillPath()
ctx.restoreGState()

// Binding strip, clipped to the page's rounded corners.
ctx.saveGState()
ctx.addPath(pagePath)
ctx.clip()
ctx.setFillColor(inkDk)
ctx.fill(CGRect(x: page.minX, y: page.minY, width: 92, height: ph))
ctx.restoreGState()

// Ruled ledger lines, lower half.
ctx.setFillColor(line)
let lx = page.minX + 92 + 56
let lw = pw - 92 - 112
// Drawn bottom-up, so i == 0 is the lowest: the short one, as though the
// entry were still being written.
for i in 0..<3 {
    let y = page.minY + 86 + CGFloat(i) * 74
    ctx.addPath(CGPath(roundedRect: CGRect(x: lx, y: y, width: i == 0 ? lw*0.55 : lw, height: 18),
                       cornerWidth: 9, cornerHeight: 9, transform: nil))
    ctx.fillPath()
}

// One bold currency mark, sized to stay readable when the icon is tiny.
let font = CTFontCreateWithName("SFProText-Bold" as CFString, 290, nil)
let attrs = [NSAttributedString.Key.font: font,
             NSAttributedString.Key.foregroundColor: ink] as CFDictionary
let attr = CFAttributedStringCreate(nil, "$" as CFString, attrs)!
let lineRun = CTLineCreateWithAttributedString(attr)
let bounds = CTLineGetBoundsWithOptions(lineRun, .useOpticalBounds)
// Sit the glyph clear above the ruled lines rather than across them.
ctx.textPosition = CGPoint(x: lx + (lw - bounds.width)/2 - bounds.minX,
                           y: page.minY + 318 - bounds.minY)
CTLineDraw(lineRun, ctx)

let image = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
