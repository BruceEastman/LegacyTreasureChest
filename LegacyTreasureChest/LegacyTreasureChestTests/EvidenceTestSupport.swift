//
//  EvidenceTestSupport.swift
//  LegacyTreasureChestTests
//
//  Synthetic media (images, PDFs) in a temporary directory, and a URLProtocol
//  stub that records requests instead of using the network. No real photos,
//  documents or personal data.
//

import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import LegacyTreasureChest

/// A temporary media folder addressed by relative paths, like MediaStorage.
final class TempMedia: AIEvidenceMediaSource, @unchecked Sendable {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ltc-evidence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func fileURL(forRelativePath path: String) -> URL {
        root.appendingPathComponent(path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func fileCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: root.path).count) ?? 0
    }

    /// Writes a synthetic JPEG of the given pixel size. `noisy` defeats JPEG
    /// compression (for size-budget tests); `gps` embeds a GPS dictionary.
    @discardableResult
    func writeJPEG(_ name: String, width: Int, height: Int, noisy: Bool = false, gps: Bool = false) throws -> String {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor(red: 0.6, green: 0.4, blue: 0.25, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            if noisy {
                var generator = SystemRandomNumberGenerator()
                let step = 4
                for y in stride(from: 0, to: height, by: step) {
                    for x in stride(from: 0, to: width, by: step) {
                        UIColor(white: CGFloat(UInt8.random(in: 0...255, using: &generator)) / 255, alpha: 1).setFill()
                        ctx.fill(CGRect(x: x, y: y, width: step, height: step))
                    }
                }
            }
        }
        let url = fileURL(forRelativePath: name)
        guard let cg = image.cgImage,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95]
        if gps {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 39.7392, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 104.9903, kCGImagePropertyGPSLongitudeRef: "W",
            ]
        }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return name
    }

    /// Writes a synthetic US Letter PDF with `pages` pages (each labeled).
    @discardableResult
    func writePDF(_ name: String, pages: Int, password: String? = nil) throws -> String {
        let url = fileURL(forRelativePath: name)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        var info: [CFString: Any] = [kCGPDFContextTitle: "SYNTHETIC TEST DOCUMENT"]
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for page in 1...max(pages, 1) {
            ctx.beginPDFPage(nil)
            UIGraphicsPushContext(ctx)
            ("SYNTHETIC TEST PAGE \(page)" as NSString).draw(
                at: CGPoint(x: 72, y: 72),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24)]
            )
            UIGraphicsPopContext()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return name
    }

    @discardableResult
    func writeBytes(_ name: String, _ data: Data) throws -> String {
        try data.write(to: fileURL(forRelativePath: name))
        return name
    }
}

/// Pixel size of a JPEG (or other image) in memory.
func imagePixelSize(_ data: Data) -> CGSize? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int,
          let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return CGSize(width: w, height: h)
}

func imageHasGPS(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
    return props[kCGImagePropertyGPSDictionary] != nil
}

// MARK: - URLProtocol stub

/// Records every request and answers from `handler`. Never touches the network.
final class StubURLProtocol: URLProtocol {
    struct Recorded {
        let url: URL
        let timeout: TimeInterval
        let body: Data
    }

    nonisolated(unsafe) static var handler: ((URLRequest, Int) throws -> (Int, Data))?
    nonisolated(unsafe) static var delay: TimeInterval = 0
    nonisolated(unsafe) private static var _recorded: [Recorded] = []
    private static let lock = NSLock()

    static var recorded: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return _recorded
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _recorded = []
        handler = nil
        delay = 0
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var cancelled = false

    override func startLoading() {
        let body = Self.readBody(request)
        Self.lock.lock()
        Self._recorded.append(Recorded(url: request.url!, timeout: request.timeoutInterval, body: body))
        let attempt = Self._recorded.count
        Self.lock.unlock()

        let respond = { [weak self] in
            guard let self, !self.cancelled else { return }
            do {
                guard let handler = Self.handler else { throw URLError(.badServerResponse) }
                let (status, data) = try handler(self.request, attempt)
                let response = HTTPURLResponse(url: self.request.url!, statusCode: status, httpVersion: nil,
                                               headerFields: ["Content-Type": "application/json"])!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
        if Self.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: respond)
        } else {
            respond()
        }
    }

    override func stopLoading() { cancelled = true }

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// A minimal valid gateway ItemAnalysis response.
func analysisResponseJSON(summary: [String: Any]? = nil, extra: [String: Any] = [:]) -> Data {
    var obj: [String: Any] = [
        "title": "Synthetic stool",
        "description": "A synthetic test item.",
        "category": "Furniture",
        "valueHints": ["valueLow": 100, "estimatedValue": 150, "valueHigh": 200, "currencyCode": "USD"],
    ]
    if let summary { obj["inputSummary"] = summary }
    obj.merge(extra) { _, new in new }
    return try! JSONSerialization.data(withJSONObject: obj)
}

func summaryJSON(primary: Bool, photos: Int, pages: Int, documents: Int? = nil, quantity: Int = 1) -> [String: Any] {
    ["contractVersion": 2, "primaryPhoto": primary, "supplementaryPhotos": photos,
     "documents": documents ?? (pages > 0 ? 1 : 0), "documentPages": pages, "quantity": quantity,
     "ownerNotes": false, "savedDescriptionParts": 0, "priorAttributes": 0]
}
