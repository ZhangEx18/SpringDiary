import Cocoa
import FlutterMacOS

final class TrayController: NSObject {
  private var statusItem: NSStatusItem?
  private var channel: FlutterMethodChannel?
  private weak var window: NSWindow?
  private var closeToTray = false
  private var exiting = false

  var shouldCloseToTray: Bool {
    statusItem != nil && closeToTray && !exiting
  }

  func attach(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(
      name: "spring_note/tray",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  func dispose() {
    hideStatusItem()
    closeToTray = false
  }

  func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    guard let window else {
      return
    }
    window.makeKeyAndOrderFront(nil)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
  }

  func hideMainWindow() {
    window?.orderOut(nil)
  }

  func exitApplication() {
    exiting = true
    hideStatusItem()
    NSApp.terminate(nil)
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "configure":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "configure expects a map", details: nil))
        return
      }
      let showTrayIcon = arguments["showTrayIcon"] as? Bool ?? false
      let nextCloseToTray = arguments["closeToTray"] as? Bool ?? false
      configure(showTrayIcon: showTrayIcon, closeToTray: nextCloseToTray)
      result(nil)
    case "dispose":
      dispose()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configure(showTrayIcon: Bool, closeToTray: Bool) {
    self.closeToTray = showTrayIcon && closeToTray
    if showTrayIcon {
      showStatusItem()
    } else {
      hideStatusItem()
    }
  }

  private func showStatusItem() {
    if statusItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      item.button?.target = self
      item.button?.action = #selector(statusItemClicked(_:))
      item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
      statusItem = item
    }

    if let image = loadStatusIcon() {
      statusItem?.button?.image = image
    } else {
      statusItem?.button?.title = "S"
    }
    statusItem?.button?.toolTip = "SpringNote"
  }

  private func loadStatusIcon() -> NSImage? {
    guard let image = NSImage(named: "TrayIcon") else {
      return nil
    }
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = false
    return image
  }

  private func hideStatusItem() {
    guard let item = statusItem else {
      return
    }
    NSStatusBar.system.removeStatusItem(item)
    statusItem = nil
  }

  private func buildMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(
        title: "打开 SpringNote",
        action: #selector(openMenuItemClicked(_:)),
        keyEquivalent: ""
      )
    )
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(
        title: "退出",
        action: #selector(exitMenuItemClicked(_:)),
        keyEquivalent: "q"
      )
    )
    menu.items.forEach { $0.target = self }
    return menu
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else {
      showMainWindow()
      return
    }
    if event.type == .rightMouseUp {
      buildMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    } else if event.type == .leftMouseUp {
      showMainWindow()
    }
  }

  @objc private func openMenuItemClicked(_ sender: NSMenuItem) {
    showMainWindow()
  }

  @objc private func exitMenuItemClicked(_ sender: NSMenuItem) {
    exitApplication()
  }
}

final class SecurityScopedDirectoryController: NSObject {
  private let defaultsKey = "spring_note.security_scoped_directory_bookmarks"
  private var channel: FlutterMethodChannel?
  private var activeUrls: [String: URL] = [:]

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "spring_note/security_scoped_directories",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "saveBookmark":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "saveBookmark expects a path", details: nil))
        return
      }
      result(saveBookmark(path: path))
    case "startAccessing":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "startAccessing expects a path", details: nil))
        return
      }
      result(startAccessing(path: path))
    case "removeBookmark":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "removeBookmark expects a path", details: nil))
        return
      }
      removeBookmark(path: path)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func saveBookmark(path: String) -> Bool {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    do {
      let bookmark = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      var bookmarks = storedBookmarks()
      bookmarks[normalizedPath(path)] = bookmark.base64EncodedString()
      UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
      _ = startAccessing(path: path)
      return true
    } catch {
      return false
    }
  }

  private func startAccessing(path: String) -> Bool {
    let key = normalizedPath(path)
    if activeUrls[key] != nil {
      return true
    }

    guard
      let bookmarkString = storedBookmarks()[key],
      let bookmark = Data(base64Encoded: bookmarkString)
    else {
      return false
    }

    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      if isStale {
        _ = saveBookmark(path: url.path)
      }
      if url.startAccessingSecurityScopedResource() {
        activeUrls[key] = url
        return true
      }
      return false
    } catch {
      return false
    }
  }

  private func removeBookmark(path: String) {
    let key = normalizedPath(path)
    if let url = activeUrls.removeValue(forKey: key) {
      url.stopAccessingSecurityScopedResource()
    }
    var bookmarks = storedBookmarks()
    bookmarks.removeValue(forKey: key)
    UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
  }

  private func storedBookmarks() -> [String: String] {
    UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
  }

  private func normalizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
  }
}
