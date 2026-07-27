import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // The Interface Builder default is a small mobile-sized window — this is
    // a desktop POS with a wide (tablet-style NavigationRail) layout, so it
    // needs real desktop dimensions from first launch, not a resize-to-taste.
    // Resized/centered BEFORE attaching the FlutterViewController (rather
    // than after) so the engine's very first frame is laid out once, at the
    // final size — resizing afterward raced with Flutter's first frame and
    // its mouse-hover tracking, tripping a framework assertion loop.
    let windowFrame = NSRect(x: 0, y: 0, width: 1280, height: 800)
    self.setFrame(windowFrame, display: true)
    self.center()

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
