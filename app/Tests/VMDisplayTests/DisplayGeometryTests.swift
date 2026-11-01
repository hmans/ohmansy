import CoreGraphics
import Testing
import VMDisplay

@Test func retinaModeRemainsDivisibleByTwoAfterDividerLayout() {
    // Regression: the running guest exposed 2944 × 1651 and GNOME hid scaling.
    let view = DisplayGeometry.alignedViewSize(CGSize(width: 1472, height: 825.5))
    #expect(view.width == 1472 && view.height == 825)
    #expect(view.width * 2 == 2944)
    #expect(view.height * 2 == 1650)
}

@Test func alignedViewFitsAvailableSpaceDuringResize() {
    for width in stride(from: 900.0, through: 920.0, by: 0.5) {
        for height in stride(from: 650.0, through: 670.0, by: 0.5) {
            let size = DisplayGeometry.alignedViewSize(CGSize(width: width, height: height))
            #expect(size.width <= width && size.height <= height)
            #expect((size.width * 2).truncatingRemainder(dividingBy: 2) == 0)
            #expect((size.height * 2).truncatingRemainder(dividingBy: 2) == 0)
        }
    }
}

@Test func followsWideSquareAndTallWindowsWithoutAnAspectRatioPreset() {
    for available in [CGSize(width: 1600, height: 700),
                      CGSize(width: 900, height: 900),
                      CGSize(width: 900, height: 1200)] {
        let view = DisplayGeometry.alignedViewSize(available)
        #expect(view.width / view.height == available.width / available.height)
    }
}
