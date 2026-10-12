import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Reads the text in an image with Vision, checks it like any copy, and blurs
/// each value it finds where it sits in the image.
enum ImageRedaction {
    static func redact(
        _ data: Data,
        detect: @Sendable (String) async throws -> Finding
    ) async throws -> Finding? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let observations = try await RecognizeTextRequest().perform(on: image)
        let lines = observations.compactMap { observation in
            observation.topCandidates(1).first.map { (text: $0, box: observation.boundingBox) }
        }
        let finding = try await detect(lines.map(\.text.string).joined(separator: "\n"))
        guard !finding.isEmpty else { return finding.read(fromImage: nil) }

        let size = CGSize(width: image.width, height: image.height)
        // Width from the value, height from its whole line, so every box on
        // a line, and every line of the same size, blurs the same height.
        let boxes = lines.flatMap { line in
            let row = line.box.toImageCoordinates(size, origin: .lowerLeft)
            return Set(finding.values).flatMap { value in
                line.text.string.ranges(of: value).compactMap { range -> CGRect? in
                    guard let span = line.text.boundingBox(for: range)?.boundingBox.toImageCoordinates(size, origin: .lowerLeft) else { return nil }
                    return CGRect(x: span.minX, y: row.minY, width: span.width, height: row.height)
                }
            }
        }
        return finding.read(fromImage: blurred(image, over: boxes).flatMap(png))
    }

    /// Strong enough that the words can't be read back: the blur scales with
    /// the tallest line it covers.
    private static func blurred(_ image: CGImage, over boxes: [CGRect]) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let tallest = boxes.map(\.height).max() else { return image }
        let blurred = input.clampedToExtent()
            .applyingGaussianBlur(sigma: max(8, tallest * 0.6))
            .cropped(to: input.extent)
        let mask = merged(boxes).reduce(CIImage.empty()) { mask, box in
            CIImage(color: .white)
                .cropped(to: box.insetBy(dx: -box.height * 0.08, dy: -box.height * 0.04))
                .composited(over: mask)
        }
        let output = blurred.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: input,
            kCIInputMaskImageKey: mask,
        ])
        return CIContext().createCGImage(output, from: input.extent)
    }

    /// A given name and a surname come back as two boxes; joined, no sliver
    /// of the space between them shows through.
    private static func merged(_ boxes: [CGRect]) -> [CGRect] {
        boxes.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }.reduce(into: []) { result, box in
            if let last = result.last,
               abs(last.midY - box.midY) < box.height * 0.5,
               box.minX - last.maxX < box.height * 0.6 {
                result[result.count - 1] = last.union(box)
            } else {
                result.append(box)
            }
        }
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
