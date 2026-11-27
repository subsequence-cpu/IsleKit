import SwiftUI

// End editing first, then let the original click reach its destination.
struct WindowEditingDismissal: NSViewRepresentable {
  func makeNSView(context: Context) -> Region { Region() }
  func updateNSView(_ view: Region, context: Context) {}
  static func dismantleNSView(_ view: Region, coordinator: ()) { view.stop() }

  final class Region: NSView {
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stop()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
        [weak self] event in
        guard let self, let window = self.window, window === event.window,
          !self.isHiddenOrHasHiddenAncestor
        else { return event }

        let field: NSView
        if let editor = window.firstResponder as? NSTextView, editor.isEditable {
          if editor.isFieldEditor {
            field = (editor.delegate as? NSTextField) ?? editor
          } else {
            field = editor.enclosingScrollView ?? editor
          }
        } else if let recorder = window.firstResponder as? ShortcutRecorder.Recorder, recorder.recording {
          field = recorder
        } else {
          return event
        }
        let point = field.convert(event.locationInWindow, from: nil)
        guard !field.bounds.intersection(field.visibleRect).contains(point) else { return event }
        window.makeFirstResponder(nil)
        return event
      }
    }

    func stop() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}
