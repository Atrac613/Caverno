// Renders one PDF page to a PNG at a requested pixel width.
//
// Used by chart_reading_probe.py, which needs page images to ask a vision
// model about a chart. Written in Swift against PDFKit rather than shelling
// out to `sips` because sips only ever renders page one of a document, and
// there is no page-selecting rasterizer on a stock macOS box.
//
// This is also a deliberate spike: if Caverno ever renders PDF pages in the
// app, the platform-channel option is exactly these few PDFKit calls, and the
// cost of that route is what this file measures.
//
//   swift render_pdf_page.swift <pdf> <page-1-based> <width-px> <out.png>

import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

let args = CommandLine.arguments

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write("render_pdf_page: \(message)\n".data(using: .utf8)!)
    exit(code)
}

guard args.count == 5 else {
    fail("usage: render_pdf_page <pdf> <page-1-based> <width-px> <out.png>", 2)
}
guard let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    fail("cannot open \(args[1])", 3)
}
guard let pageNumber = Int(args[2]), let width = Int(args[3]), width > 0 else {
    fail("page and width must be positive integers", 2)
}
guard pageNumber >= 1, pageNumber <= document.pageCount else {
    fail("page \(pageNumber) is outside 1...\(document.pageCount)", 4)
}
guard let page = document.page(at: pageNumber - 1) else {
    fail("page \(pageNumber) could not be read", 4)
}

let box = page.bounds(for: .mediaBox)
guard box.width > 0 else { fail("page \(pageNumber) has no media box", 4) }
let scale = CGFloat(width) / box.width
let size = CGSize(width: box.width * scale, height: box.height * scale)

// `thumbnail(of:for:)` rasterizes the page at whatever size is asked for; the
// name is historical, not a quality ceiling.
let rendered = page.thumbnail(of: size, for: .mediaBox)
guard let tiff = rendered.tiffRepresentation,
    let source = CGImageSourceCreateWithData(tiff as CFData, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fail("page \(pageNumber) could not be rasterized", 5)
}
guard
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: args[4]) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fail("cannot write \(args[4])", 5)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("PNG encode failed", 5) }

// The caller reads this back to record what it actually measured.
print("\(Int(size.width)) \(Int(size.height)) \(document.pageCount)")
