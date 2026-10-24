import AppKit
import CoreGraphics

// Menu bar требует простой векторной формы: иллюстрация app icon теряет детали при 18 px.
// Рисуем собственный силуэт кота с речевым хвостиком, оставляя настоящие прозрачные глаза.
guard CommandLine.arguments.count == 2 else {
    fputs("Укажите путь выходного PDF.\n", stderr)
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
var bounds = CGRect(x: 0, y: 0, width: 26, height: 24)
guard let consumer = CGDataConsumer(url: output as CFURL),
      let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
    fputs("Не удалось создать PDF.\n", stderr)
    exit(1)
}
context.beginPDFPage(nil)
let cat = CGMutablePath()
cat.move(to: CGPoint(x: 5, y: 6))
cat.addLine(to: CGPoint(x: 3, y: 1))
cat.addLine(to: CGPoint(x: 11, y: 4))
cat.addCurve(to: CGPoint(x: 23, y: 14),
             control1: CGPoint(x: 24, y: 1), control2: CGPoint(x: 27, y: 9))
cat.addLine(to: CGPoint(x: 23, y: 22))
cat.addLine(to: CGPoint(x: 17, y: 18))
cat.addQuadCurve(to: CGPoint(x: 9, y: 18), control: CGPoint(x: 13, y: 20))
cat.addLine(to: CGPoint(x: 3, y: 22))
cat.addLine(to: CGPoint(x: 3, y: 15))
cat.addQuadCurve(to: CGPoint(x: 5, y: 6), control: CGPoint(x: 0, y: 10))
cat.closeSubpath()
cat.addEllipse(in: CGRect(x: 7.2, y: 10.5, width: 2.2, height: 2.2))
cat.addEllipse(in: CGRect(x: 16.2, y: 10.5, width: 2.2, height: 2.2))
context.addPath(cat)
context.setFillColor(CGColor(gray: 0, alpha: 1))
// Even-odd winding вычитает глаза из силуэта без белой подложки, сохраняя template-окрашивание.
context.drawPath(using: .eoFill)
context.endPDFPage()
context.closePDF()
print(output.path)
