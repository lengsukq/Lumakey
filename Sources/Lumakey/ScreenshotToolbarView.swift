import LumakeyCore
import SwiftUI

enum ScreenshotToolbarAction: Sendable {
    case undo, clear, syncClipboard, ocr, cutout, pin, save, cancel, copy
}

struct ScreenshotToolbarView: View {
    @ObservedObject var session: ScreenshotSessionState
    let onAction: (ScreenshotToolbarAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(AnnotationToolKind.allCases) { tool in
                    toolButton(tool)
                }

                Divider().frame(height: 18).padding(.horizontal, 4)

                actionIconButton("arrow.uturn.backward", label: "撤销", disabled: session.annotations.isEmpty) {
                    onAction(.undo)
                }
                actionIconButton("trash", label: "清空", disabled: session.annotations.isEmpty) {
                    onAction(.clear)
                }

                Divider().frame(height: 18).padding(.horizontal, 4)

                actionTextButton("text.viewfinder", title: "OCR", tint: .purple) { onAction(.ocr) }
                actionTextButton("person.crop.rectangle", title: "抠图", tint: .orange) { onAction(.cutout) }
                actionTextButton("pin.fill", title: "钉图", tint: .teal) { onAction(.pin) }
                actionTextButton("square.and.arrow.down", title: "保存", tint: .secondary) { onAction(.save) }

                Button { onAction(.cancel) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                }
                .buttonStyle(.plain)
                .help("取消截图 (Esc)")

                Button { onAction(.copy) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("完成")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("完成截图（已自动复制到剪贴板 · Enter / ⌘C / 双击）")
            }

            if session.activeTool != .move {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(AnnotationStrokeSize.allCases) { size in
                            Button {
                                session.strokeSize = size
                            } label: {
                                Text(size.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(session.strokeSize == size ? .white : LiquidColors.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        session.strokeSize == size ? Color.accentColor : LiquidColors.pillSurface,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider().frame(height: 14)

                    if session.activeTool != .mosaic {
                        HStack(spacing: 6) {
                            ForEach(AnnotationRGBColor.presets, id: \.self) { color in
                                let selected = session.selectedColor == color
                                Button {
                                    session.selectedColor = color
                                } label: {
                                    Circle()
                                        .fill(Color(cgColor: color.cgColor))
                                        .frame(width: 15, height: 15)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white, lineWidth: selected ? 2.2 : 0.8)
                                                .padding(selected ? -2 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Divider().frame(height: 14)
                    }

                    Text("⌘Z 撤销 · 双击完成")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LiquidColors.pillBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
    }

    private func toolButton(_ tool: AnnotationToolKind) -> some View {
        let active = session.activeTool == tool
        return Button {
            session.commitTextAnnotation()
            session.activeTool = tool
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? .white : .primary)
                .frame(width: 28, height: 28)
                .background(
                    active ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }

    private func actionIconButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? .tertiary : .primary)
                .frame(width: 26, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(label)
    }

    private func actionTextButton(_ symbol: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
