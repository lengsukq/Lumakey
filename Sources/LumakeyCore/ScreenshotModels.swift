import CoreGraphics
import Foundation

public enum AnnotationToolKind: String, CaseIterable, Identifiable, Sendable {
    case move, rect, ellipse, arrow, pen, highlighter, mosaic, counter, text

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .move: return "移动"
        case .rect: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .highlighter: return "荧光笔"
        case .mosaic: return "马赛克"
        case .counter: return "序号"
        case .text: return "文字"
        }
    }

    public var symbolName: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .mosaic: return "checkerboard.rectangle"
        case .counter: return "1.circle"
        case .text: return "textformat"
        }
    }
}

public struct AnnotationRGBColor: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public static let presets: [AnnotationRGBColor] = [
        AnnotationRGBColor(red: 1.0, green: 0.23, blue: 0.19),
        AnnotationRGBColor(red: 1.0, green: 0.58, blue: 0.0),
        AnnotationRGBColor(red: 1.0, green: 0.80, blue: 0.0),
        AnnotationRGBColor(red: 0.20, green: 0.78, blue: 0.35),
        AnnotationRGBColor(red: 0.0, green: 0.48, blue: 1.0),
        AnnotationRGBColor(red: 1.0, green: 1.0, blue: 1.0)
    ]
}

public enum AnnotationStrokeSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .small: return "细"
        case .medium: return "中"
        case .large: return "粗"
        }
    }

    public var lineWidth: CGFloat {
        switch self {
        case .small: return 2.5
        case .medium: return 5.0
        case .large: return 9.0
        }
    }

    public var mosaicBrushRadius: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 18
        case .large: return 28
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 18
        case .large: return 24
        }
    }
}

public struct ScreenshotAnnotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let tool: AnnotationToolKind
    public let color: AnnotationRGBColor
    public let strokeSize: AnnotationStrokeSize
    public var points: [CGPoint]
    public var text: String
    public var counterIndex: Int

    public init(
        id: UUID = UUID(),
        tool: AnnotationToolKind,
        color: AnnotationRGBColor,
        strokeSize: AnnotationStrokeSize,
        points: [CGPoint],
        text: String = "",
        counterIndex: Int = 1
    ) {
        self.id = id
        self.tool = tool
        self.color = color
        self.strokeSize = strokeSize
        self.points = points
        self.text = text
        self.counterIndex = counterIndex
    }
}
