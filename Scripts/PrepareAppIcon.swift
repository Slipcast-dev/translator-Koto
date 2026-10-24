import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Локальная подготовка разрешена пользователем после двух сетевых ошибок image_gen.
/// Алгоритм удаляет только фон, достижимый от границы без пересечения тёмной плитки.
enum IconPreparationError: Error {
    case invalidArguments, unreadableImage, unsupportedDimensions, contextCreation, tileNotFound, encoding
}

func prepareIcon(sourceURL: URL, outputURL: URL) throws -> [String: Any] {
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw IconPreparationError.unreadableImage
    }
    let width = image.width
    let height = image.height
    guard width >= 512, height >= 512, width <= 8192, height <= 8192 else {
        throw IconPreparationError.unsupportedDimensions
    }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let decoded = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(
            data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard decoded else { throw IconPreparationError.contextCreation }

    // Тёмный край исходной графитовой плитки — барьер, окружающий светлого кота.
    // Flood fill вместо глобального удаления белого сохраняет морду и другие светлые детали.
    var exterior = [Bool](repeating: false, count: width * height)
    var queue: [Int] = []
    queue.reserveCapacity(width * height / 2)
    func addExterior(_ index: Int) {
        guard !exterior[index] else { return }
        let p = index * 4
        let luminance = 0.2126 * Double(pixels[p]) + 0.7152 * Double(pixels[p + 1])
            + 0.0722 * Double(pixels[p + 2])
        guard luminance > 140 else { return }
        exterior[index] = true
        queue.append(index)
    }
    for x in 0..<width {
        addExterior(x)
        addExterior((height - 1) * width + x)
    }
    for y in 0..<height {
        addExterior(y * width)
        addExterior(y * width + width - 1)
    }
    var cursor = 0
    while cursor < queue.count {
        let i = queue[cursor]
        cursor += 1
        let x = i % width
        let y = i / width
        if x > 0 { addExterior(i - 1) }
        if x + 1 < width { addExterior(i + 1) }
        if y > 0 { addExterior(i - width) }
        if y + 1 < height { addExterior(i + width) }
    }
    var minX = width, minY = height, maxX = 0, maxY = 0
    for i in 0..<(width * height) {
        if exterior[i] {
            // Для premultiplied alpha прозрачный пиксель имеет нулевые RGB, иначе появится ореол.
            let p = i * 4
            pixels[p] = 0
            pixels[p + 1] = 0
            pixels[p + 2] = 0
            pixels[p + 3] = 0
        } else {
            minX = min(minX, i % width)
            minY = min(minY, i / width)
            maxX = max(maxX, i % width)
            maxY = max(maxY, i / width)
        }
    }
    guard minX > 0, minY > 0, maxX < width - 1, maxY < height - 1,
          maxX - minX > width / 2, maxY - minY > height / 2 else {
        throw IconPreparationError.tileNotFound
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let masked = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
          ),
          let tile = masked.cropping(to: CGRect(
            x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1
          )),
          let target = CGContext(
            data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
            bytesPerRow: 1024 * 4, space: colorSpace, bitmapInfo: bitmapInfo
          ) else { throw IconPreparationError.contextCreation }

    // Равномерные поля и aspect-fit не меняют пропорции выбранной иллюстрации.
    let scale = 864.0 / Double(max(tile.width, tile.height))
    let size = CGSize(width: Double(tile.width) * scale, height: Double(tile.height) * scale)
    target.interpolationQuality = .high
    target.draw(tile, in: CGRect(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2,
                                 width: size.width, height: size.height))
    guard let output = target.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { throw IconPreparationError.encoding }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconPreparationError.encoding }
    return [
        "source_width": width, "source_height": height,
        "output_width": 1024, "output_height": 1024,
        "exterior_pixels_removed": queue.count,
        "tile_bounds": [minX, minY, maxX, maxY],
        "transparent_margin_pixels": 80,
        "method": "edge-connected exterior mask; enclosed cat preserved; native CoreGraphics"
    ]
}

do {
    guard CommandLine.arguments.count == 3 else { throw IconPreparationError.invalidArguments }
    let result = try prepareIcon(
        sourceURL: URL(fileURLWithPath: CommandLine.arguments[1]),
        outputURL: URL(fileURLWithPath: CommandLine.arguments[2])
    )
    let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} catch {
    fputs("Подготовка иконки не завершена: \(error)\n", stderr)
    exit(1)
}
