import CoreGraphics
import DanmakuCore
import Testing

@testable import DanmakuText

struct TextTests {
    let style = TextStyle(fontName: "PingFang SC", weight: .semibold, outline: .stroke, strokeWidth: 1)

    @Test func measuredSizeMatchesBitmap() throws {
        let measurer = CoreTextMeasurer(style: style)
        for (text, size) in [("Hello 世界", 25.0), ("😀 emoji", 36), ("多行\n文本", 18)] {
            let measured = measurer.measure(text, fontSize: size)
            let image = try #require(
                DanmakuRasterizer.render(
                    GlyphKey(text: text, fontSize: size, color: 0xFFFFFF),
                    style: RasterStyle(text: style, strokeColor: 0, colorfulGradient: true, scale: 2)))
            #expect(image.size == measured)
            #expect(image.image.width == Int((measured.width * 2).rounded(.up)))
            #expect(measured.width > size)
        }
    }

    @Test func multilineIsTaller() {
        let m = CoreTextMeasurer(style: style)
        #expect(m.measure("a\nb", fontSize: 25).height > m.measure("a", fontSize: 25).height * 1.8)
    }

    @Test func unknownFontFallsBack() throws {
        var s = style
        s.fontName = "No Such Font 123"
        #expect(CoreTextMeasurer(style: s).measure("测试", fontSize: 25).width > 40)
    }

    @Test func gradientRenders() throws {
        let image = DanmakuRasterizer.render(
            GlyphKey(text: "VIP", fontSize: 25, color: 0xFFFFFF, colorful: true),
            style: RasterStyle(text: style, strokeColor: 0, colorfulGradient: true, scale: 1))
        #expect(image != nil)
    }
}
