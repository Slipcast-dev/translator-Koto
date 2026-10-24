import Foundation
import CoreGraphics
import ImageIO

// Проверка читает alpha, не меняя изображение: наличие PNG-канала само по себе не доказывает прозрачность.
guard CommandLine.arguments.count == 2,
      let source = CGImageSourceCreateWithURL(
        URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil
      ),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    fputs("Не удалось прочитать PNG.\n", stderr)
    exit(1)
}
let width = image.width, height = image.height
var bytes = [UInt8](repeating: 0, count: width * height * 4)
let success = bytes.withUnsafeMutableBytes { storage -> Bool in
    guard let context = CGContext(
        data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: space,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
}
guard success else { exit(1) }
let transparent = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] == 0 }.count
let opaque = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] == 255 }.count
let corners = [0, width - 1, (height - 1) * width, width * height - 1].map { bytes[$0 * 4 + 3] }
let valid = width == 1024 && height == 1024 && corners.allSatisfy { $0 == 0 }
    && transparent > 200_000 && opaque > 500_000
let result: [String: Any] = [
    "width": width, "height": height, "transparent_pixels": transparent,
    "opaque_pixels": opaque, "corner_alpha": corners, "passed": valid
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
exit(valid ? 0 : 1)
