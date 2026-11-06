import SwiftUI
import DosMacVM

#if os(macOS)
import AppKit
import CoreGraphics

struct GuestTextSheet: View {
    @ObservedObject var model: MachineLibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Type text in guest").font(.title2.bold())
            Text("Focus the destination inside DOS or Windows before opening this panel. Paste a path or text here; DosMac types it using the guest’s US keyboard layout. Each line break presses Enter.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(.body, design: .monospaced))
                .frame(height: 150).disabled(sending)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack {
                if sending { ProgressView().controlSize(.small); Text("Typing…") }
                Spacer()
                Button(sending ? "Stop" : "Cancel") { task?.cancel(); dismiss() }
                Button("Type text") {
                    do {
                        _ = try GuestTyping.strokes(for: text)
                        sending = true; error = nil
                        task = Task {
                            do { try await model.session.typeText(text); dismiss() }
                            catch is CancellationError { }
                            catch { self.error = error.localizedDescription }
                            sending = false
                        }
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
                    .disabled(sending || text.isEmpty || !model.active || model.busy)
            }
        }.padding(24).frame(width: 580)
            .interactiveDismissDisabled(sending)
            .onDisappear { task?.cancel() }
    }
}

struct MachineDisplayView: NSViewRepresentable {
    let image: CGImage?
    let session: MachineSession
    let inputEnabled: Bool
    let absolutePointer: Bool
    let onCapture: (Bool) -> Void

    func makeNSView(context: Context) -> GuestDisplayView {
        let view = GuestDisplayView(); view.session = session; view.onCapture = onCapture
        return view
    }
    func updateNSView(_ view: GuestDisplayView, context: Context) {
        view.inputEnabled = inputEnabled
        if view.absolutePointer != absolutePointer { view.releaseCapture(); view.absolutePointer = absolutePointer }
        if !inputEnabled { view.releaseCapture() }
        view.frameImage = image; view.needsDisplay = true
    }
    static func dismantleNSView(_ view: GuestDisplayView, coordinator: ()) { view.releaseCapture() }
}

@MainActor
final class GuestDisplayView: NSView {
    var frameImage: CGImage?
    weak var session: MachineSession?
    var onCapture: ((Bool) -> Void)?
    var inputEnabled = true
    var absolutePointer = false
    private var seamlessCursorHidden = false
    private var absoluteEvents: [(Int, Int, String?, Bool)] = []
    private var absoluteInputTask: Task<Void, Never>?
    private var captured = false
    private var tracking: NSTrackingArea?
    private var keys = Set<UInt16>()
    private var buttons = Set<String>()
    private var observer: NSObjectProtocol?
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func resignFirstResponder() -> Bool { releaseCapture(); return super.resignFirstResponder() }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            releaseCapture()
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseCapture() }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard let image = frameImage, let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let rect = CGRect(x: (bounds.width - CGFloat(image.width) * scale) / 2, y: (bounds.height - CGFloat(image.height) * scale) / 2, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.interpolationQuality = .none; context.draw(image, in: rect)
    }

    override func mouseDown(with event: NSEvent) {
        guard inputEnabled else { return }
        window?.makeFirstResponder(self)
        if absolutePointer { absolute(event, button: "left", down: true); return }
        if !captured { captured = true; NSCursor.hide(); CGAssociateMouseAndMouseCursorPosition(boolean_t(0)); onCapture?(true); return }
        button("left", down: true)
    }
    override func mouseUp(with event: NSEvent) {
        if absolutePointer { absolute(event, button: "left", down: false) }
        else if buttons.contains("left") { button("left", down: false) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if absolutePointer { window?.makeFirstResponder(self); absolute(event, button: "right", down: true) }
        else if captured { button("right", down: true) }
    }
    override func rightMouseUp(with event: NSEvent) {
        if absolutePointer { absolute(event, button: "right", down: false) }
        else if buttons.contains("right") { button("right", down: false) }
    }
    override func mouseEntered(with event: NSEvent) { if absolutePointer { absolute(event) } }
    override func mouseExited(with event: NSEvent) { if absolutePointer { releaseAbsoluteButtons(); showHostCursor() } }
    override func mouseMoved(with event: NSEvent) { move(event) }
    override func mouseDragged(with event: NSEvent) { move(event) }
    override func rightMouseDragged(with event: NSEvent) { move(event) }

    private func button(_ name: String, down: Bool) {
        if down { buttons.insert(name) } else { buttons.remove(name) }
        Task { try? await session?.pointer(dx: 0, dy: 0, button: name, down: down) }
    }
    private func move(_ event: NSEvent) {
        guard inputEnabled else { return }
        if absolutePointer { absolute(event); return }
        guard captured else { return }
        let dx = Int(event.deltaX.rounded()), dy = Int(event.deltaY.rounded())
        Task { try? await session?.pointer(dx: dx, dy: dy) }
    }
    private func showHostCursor() {
        if seamlessCursorHidden { seamlessCursorHidden = false; NSCursor.unhide() }
    }
    private func releaseAbsoluteButtons() {
        // A drag leaving the guest must never leave a button pressed inside Windows.
        let released = buttons; buttons.removeAll()
        for name in released { enqueueAbsolute(absoluteEvents.last?.0 ?? lastAbsolute.0, absoluteEvents.last?.1 ?? lastAbsolute.1, name, false) }
    }
    private var lastAbsolute = (0, 0)
    private func absolute(_ event: NSEvent, button: String? = nil, down: Bool = false) {
        guard inputEnabled, let image = frameImage else { return }
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let rect = NSRect(x: (bounds.width - CGFloat(image.width) * scale) / 2, y: (bounds.height - CGFloat(image.height) * scale) / 2, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let point = convert(event.locationInWindow, from: nil)
        guard rect.contains(point) else { releaseAbsoluteButtons(); showHostCursor(); return }
        if !seamlessCursorHidden, window?.isKeyWindow == true { NSCursor.hide(); seamlessCursorHidden = true }
        let x = GuestPointer.coordinate(Double(point.x - rect.minX), extent: Double(rect.width))
        let y = GuestPointer.coordinate(Double(rect.maxY - point.y), extent: Double(rect.height))
        if let button { if down { buttons.insert(button) } else { buttons.remove(button) } }
        lastAbsolute = (x, y); enqueueAbsolute(x, y, button, down)
    }
    private func enqueueAbsolute(_ x: Int, _ y: Int, _ button: String?, _ down: Bool) {
        // Coalesce movement while keeping every button transition in order.
        if button == nil, absoluteEvents.last?.2 == nil, !absoluteEvents.isEmpty { absoluteEvents.removeLast() }
        absoluteEvents.append((x, y, button, down))
        guard absoluteInputTask == nil else { return }
        absoluteInputTask = Task { [weak self] in
            guard let self else { return }
            defer { self.absoluteInputTask = nil }
            while !self.absoluteEvents.isEmpty {
                let event = self.absoluteEvents.removeFirst()
                try? await self.session?.absolutePointer(x: event.0, y: event.1, button: event.2, down: event.3)
            }
        }
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { super.keyDown(with: event); return }
        guard inputEnabled else { return }
        guard let code = Self.keycodes[event.keyCode] else { return }
        keys.insert(event.keyCode); Task { try? await session?.key(qcode: code, down: true) }
    }
    override func keyUp(with event: NSEvent) {
        guard keys.remove(event.keyCode) != nil, let code = Self.keycodes[event.keyCode] else { return }
        Task { try? await session?.key(qcode: code, down: false) }
    }
    override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains([.control, .option]) { releaseCapture(); return }
        guard inputEnabled else { return }
        if event.keyCode == 57 { Task { try? await session?.tap("caps_lock") }; return }
        guard let code = Self.keycodes[event.keyCode] else { return }
        let down = !keys.contains(event.keyCode)
        if down { keys.insert(event.keyCode) } else { keys.remove(event.keyCode) }
        Task { try? await session?.key(qcode: code, down: down) }
    }

    func releaseCapture() {
        showHostCursor()
        if absolutePointer { releaseAbsoluteButtons() }
        guard captured || !keys.isEmpty || !buttons.isEmpty else { return }
        if captured { captured = false; CGAssociateMouseAndMouseCursorPosition(boolean_t(1)); NSCursor.unhide(); onCapture?(false) }
        let released = keys.compactMap { Self.keycodes[$0] }; keys.removeAll()
        let releasedButtons = buttons; buttons.removeAll()
        Task { [weak session] in
            for code in released { try? await session?.key(qcode: code, down: false) }
            for name in releasedButtons { try? await session?.pointer(dx: 0, dy: 0, button: name, down: false) }
        }
    }

    static let keycodes: [UInt16: String] = [0:"a",1:"s",2:"d",3:"f",4:"h",5:"g",6:"z",7:"x",8:"c",9:"v",11:"b",12:"q",13:"w",14:"e",15:"r",16:"y",17:"t",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"equal",25:"9",26:"7",27:"minus",28:"8",29:"0",30:"bracket_right",31:"o",32:"u",33:"bracket_left",34:"i",35:"p",36:"ret",37:"l",38:"j",39:"apostrophe",40:"k",41:"semicolon",42:"backslash",43:"comma",44:"slash",45:"n",46:"m",47:"dot",48:"tab",49:"spc",50:"grave_accent",51:"backspace",53:"esc",56:"shift",58:"alt",59:"ctrl",60:"shift_r",61:"alt_r",62:"ctrl_r",65:"kp_decimal",67:"kp_multiply",69:"kp_add",75:"kp_divide",76:"kp_enter",78:"kp_subtract",82:"kp_0",83:"kp_1",84:"kp_2",85:"kp_3",86:"kp_4",87:"kp_5",88:"kp_6",89:"kp_7",91:"kp_8",92:"kp_9",96:"f5",97:"f6",98:"f7",99:"f3",100:"f8",101:"f9",103:"f11",109:"f10",111:"f12",115:"home",116:"pgup",117:"delete",118:"f4",119:"end",120:"f2",121:"pgdn",122:"f1",123:"left",124:"right",125:"down",126:"up"]
}
#endif
