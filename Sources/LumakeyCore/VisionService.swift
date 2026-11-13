import CoreGraphics
import CoreImage
import CoreML
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

public struct VisionTextAnalysis: Sendable, Hashable {
    public let recognizedText: String
    public let barcodes: [String]
}

public enum VisionService {
    private static func bindCPUComputeDevice(_ request: VNRequest) {
        guard let cpu = MLComputeDevice.allComputeDevices.first(where: {
            if case .cpu = $0 { return true }
            return false
        }), let stages = try? request.supportedComputeStageDevices else { return }
        for (stage, devices) in stages where devices.contains(cpu) {
            request.setComputeDevice(cpu, for: stage)
        }
    }

    public static func analyzeTextAndBarcodes(at imageURL: URL) throws -> VisionTextAnalysis {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        textRequest.usesLanguageCorrection = true
        bindCPUComputeDevice(textRequest)

        let barcodeRequest = VNDetectBarcodesRequest()
        bindCPUComputeDevice(barcodeRequest)
        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        do {
            try handler.perform([textRequest, barcodeRequest])
        } catch {
            throw LumakeyError.visionFailed(error.localizedDescription)
        }

        let lines = (textRequest.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        let codes = (barcodeRequest.results ?? []).compactMap(\.payloadStringValue)
        return VisionTextAnalysis(
            recognizedText: lines.joined(separator: "\n"),
            barcodes: Array(Set(codes)).sorted()
        )
    }

    public static func liftForegroundSubject(from imageURL: URL) throws -> URL {
        let request = VNGenerateForegroundInstanceMaskRequest()
        bindCPUComputeDevice(request)
        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw LumakeyError.visionFailed(error.localizedDescription)
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw LumakeyError.visionFailed("未检测到可剥离的前景主体。")
        }

        let maskedBuffer: CVPixelBuffer
        do {
            maskedBuffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
        } catch {
            throw LumakeyError.visionFailed("主体遮罩生成失败：\(error.localizedDescription)")
        }

        let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw LumakeyError.visionFailed("无法将抠图结果渲染为图像。")
        }

        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-cutouts", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outURL = outDir.appendingPathComponent("cutout-\(UUID().uuidString).png")

        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw LumakeyError.visionFailed("无法创建透明 PNG 输出文件。")
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw LumakeyError.visionFailed("写入透明 PNG 文件失败。")
        }
        return outURL
    }
}
