import XCTest
import UIKit
@testable import cc_dashboard_ios

@MainActor
final class AppIconTests: XCTestCase {

    func testAppIconIsNotPlaceholder() {
        guard let iconPath = findCompiledIconPath() else {
            XCTFail("No AppIcon found in app bundle")
            return
        }

        guard let image = UIImage(contentsOfFile: iconPath) else {
            XCTFail("Could not load icon as UIImage from \(iconPath)")
            return
        }

        guard let cgImage = image.cgImage else {
            XCTFail("Could not get CGImage from icon")
            return
        }

        let isPlaceholder = checkIfGrayscalePlaceholder(cgImage: cgImage)
        XCTAssertFalse(
            isPlaceholder,
            "AppIcon appears to be a placeholder image (mostly grayscale). Please provide a real icon."
        )
    }

    /// 在 app bundle 中查找编译后的 AppIcon PNG
    private func findCompiledIconPath() -> String? {
        let bundle = Bundle.main
        let resourcePath = bundle.bundlePath

        // Xcode 编译后会在 app bundle 根目录放置 AppIcon60x60@2x.png 等文件
        let possibleNames = ["AppIcon60x60@2x", "AppIcon60x60@3x", "AppIcon"]
        for name in possibleNames {
            if let path = bundle.path(forResource: name, ofType: "png") {
                return path
            }
        }

        // 兜底：遍历 bundle 目录找包含 AppIcon 的 png
        if let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
            for file in files where file.hasPrefix("AppIcon") && file.hasSuffix(".png") {
                return resourcePath + "/" + file
            }
        }

        return nil
    }

    /// 采样像素并判断图像是否主要是灰度（占位符特征）
    private func checkIfGrayscalePlaceholder(cgImage: CGImage) -> Bool {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        guard width > 0, height > 0 else { return true }

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var colorfulPixels = 0
        let totalPixels = width * height
        let sampleCount = min(totalPixels, 5000)
        let step = totalPixels / sampleCount

        for i in stride(from: 0, to: totalPixels * bytesPerPixel, by: bytesPerPixel * step) {
            let r = Double(pixelData[i])
            let g = Double(pixelData[i + 1])
            let b = Double(pixelData[i + 2])

            // 忽略透明像素
            let a = Double(pixelData[i + 3])
            guard a > 10 else { continue }

            let maxDiff = max(abs(r - g), abs(g - b), abs(r - b))
            if maxDiff > 25 {
                colorfulPixels += 1
            }
        }

        let ratio = Double(colorfulPixels) / Double(sampleCount)
        // 真实图标应该有不少于 5% 的彩色像素；占位符大部分是灰白
        return ratio < 0.05
    }
}
