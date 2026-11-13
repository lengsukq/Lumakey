import AppKit
import LumakeyCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceItemFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

@MainActor
final class WorkspaceCanvasController: ObservableObject {
    @Published var marqueeRect: CGRect?
    @Published var hoveredDropID: String?
    var itemFrames: [String: CGRect] = [:]

    private var isTrackingMarquee = false
    private var baseSelectionIDs: Set<String> = []
    private var mergeMode = false
    var isDraggingItem = false

    func beginItemDrag(viewModel: AppViewModel) {
        isDraggingItem = true
        isTrackingMarquee = false
        if marqueeRect != nil { marqueeRect = nil }
        let vm = viewModel
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            Task { @MainActor in
                self?.endMarquee()
                vm.activeDragURLs = []
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    func updateMarquee(start: CGPoint, current: CGPoint, viewModel: AppViewModel, pane: PaneSide) {
        if NSEvent.pressedMouseButtons & 1 == 0 {
            endMarquee()
            return
        }
        if isDraggingItem { return }

        if !isTrackingMarquee {
            isTrackingMarquee = true
            viewModel.activePane = pane
            let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            mergeMode = flags.contains(.command) || flags.contains(.shift)
            baseSelectionIDs = mergeMode ? Set(viewModel.selectedEntries(in: pane).map(\.id)) : []
        }

        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        marqueeRect = rect

        var hits = Set<String>()
        for (id, frame) in itemFrames where frame.intersects(rect) {
            hits.insert(id)
        }
        viewModel.applyMarqueeSelection(ids: mergeMode ? baseSelectionIDs.union(hits) : hits, in: pane)
    }

    func endMarquee() {
        if marqueeRect != nil { marqueeRect = nil }
        isTrackingMarquee = false
        isDraggingItem = false
    }
}

struct WorkspaceMarqueeContainer<Content: View>: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var canvas: WorkspaceCanvasController
    let pane: PaneSide
    let state: PaneState
    let spaceName: String
    private let content: () -> Content

    init(
        viewModel: AppViewModel,
        canvas: WorkspaceCanvasController,
        pane: PaneSide,
        state: PaneState,
        spaceName: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.viewModel = viewModel
        self.canvas = canvas
        self.pane = pane
        self.state = state
        self.spaceName = spaceName
        self.content = content
    }

    var body: some View {
        let paneDropID = "pane:\(pane.rawValue)"
        GeometryReader { viewport in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(minWidth: max(1, viewport.size.width), minHeight: max(1, viewport.size.height))
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.clearWorkspaceSelection(in: pane) }
                            .contextMenu { WorkspaceCanvasContextMenu(viewModel: viewModel, pane: pane, state: state) }

                        content()
                    }
                    .frame(minWidth: max(1, viewport.size.width), minHeight: max(1, viewport.size.height), alignment: .topLeading)
                }

                if let rect = canvas.marqueeRect, rect.width > 1 || rect.height > 1 {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.cyan.opacity(0.15))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.cyan.opacity(0.7), lineWidth: 1.1)
                        }
                        .frame(width: max(2, rect.width), height: max(2, rect.height))
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: spaceName)
        .onPreferenceChange(WorkspaceItemFramesKey.self) { frames in
            canvas.itemFrames = frames
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named(spaceName))
                .onChanged { value in
                    canvas.updateMarquee(start: value.startLocation, current: value.location, viewModel: viewModel, pane: pane)
                }
                .onEnded { _ in canvas.endMarquee() }
        )
        .overlay {
            if canvas.hoveredDropID == paneDropID {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, dash: [6, 4]))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [UTType.fileURL],
            delegate: WorkspaceDropTargetDelegate(
                viewModel: viewModel,
                canvas: canvas,
                destinationURL: state.currentDirectory,
                targetID: paneDropID,
                targetPane: pane
            )
        )
    }
}

struct WorkspaceDropTargetDelegate: DropDelegate {
    let viewModel: AppViewModel
    let canvas: WorkspaceCanvasController
    let destinationURL: URL
    let targetID: String
    let targetPane: PaneSide

    func validateDrop(info: DropInfo) -> Bool {
        !viewModel.activeDragURLs.isEmpty || info.hasItemsConforming(to: [UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        canvas.hoveredDropID = targetID
    }

    func dropExited(info: DropInfo) {
        if canvas.hoveredDropID == targetID { canvas.hoveredDropID = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: NSEvent.modifierFlags.contains(.option) ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if canvas.hoveredDropID == targetID { canvas.hoveredDropID = nil }
        canvas.endMarquee()
        let copyMode = NSEvent.modifierFlags.contains(.option)

        if !viewModel.activeDragURLs.isEmpty {
            let urls = viewModel.activeDragURLs
            viewModel.activeDragURLs = []
            viewModel.handleDroppedURLs(urls, to: destinationURL, copy: copyMode, targetPane: targetPane)
            return true
        }

        let providers = info.itemProviders(for: [UTType.fileURL])
        guard !providers.isEmpty else { return false }
        let collector = DroppedURLCollector()
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.append(url)
                }
                group.leave()
            }
        }
        let vm = viewModel
        let dst = destinationURL
        let pane = targetPane
        group.notify(queue: .main) {
            let loaded = collector.snapshot()
            Task { @MainActor in vm.handleDroppedURLs(loaded, to: dst, copy: copyMode, targetPane: pane) }
        }
        return true
    }
}

private final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func append(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    func snapshot() -> [URL] { lock.lock(); defer { lock.unlock() }; return urls }
}
