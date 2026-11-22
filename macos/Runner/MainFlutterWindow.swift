import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // "notoryx/screen_capture": while SARNEG screens show, keep this window
    // out of screen sharing and capture where macOS allows it.
    let capture = FlutterMethodChannel(
      name: "notoryx/screen_capture",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    capture.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setBlocked", let blocked = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.sharingType = blocked ? .none : .readOnly
      result(nil)
    }

    super.awakeFromNib()
  }
}
