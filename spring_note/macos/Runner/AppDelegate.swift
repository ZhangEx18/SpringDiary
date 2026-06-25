import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  let trayController = TrayController()

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    if trayController.shouldCloseToTray {
      trayController.hideMainWindow()
      return false
    }
    return true
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    trayController.showMainWindow()
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
