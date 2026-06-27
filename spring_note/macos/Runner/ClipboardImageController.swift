import Cocoa
import FlutterMacOS

class ClipboardImageController {
  private let allowedImageExtensions: Set<String> = [
    "png",
    "jpg",
    "jpeg",
    "gif",
    "webp",
    "bmp",
    "heic",
    "svg",
    "jfif",
  ]

  private var channel: FlutterMethodChannel?

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "spring_note/clipboard_image",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }

      switch call.method {
      case "readImageFiles":
        result(self.readImageFiles())
      case "readPngImage":
        result(self.readPngImage())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func readImageFiles() -> [String] {
    let pasteboard = NSPasteboard.general
    var paths: [String] = []

    if let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] {
      for url in urls {
        appendImageFile(url.path, to: &paths)
      }
    }

    // Keep the legacy filename pasteboard type for older apps that still write it.
    let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    if let filenames = pasteboard.propertyList(forType: filenamesType) as? [String] {
      for path in filenames {
        appendImageFile(path, to: &paths)
      }
    }

    return paths
  }

  private func appendImageFile(_ path: String, to paths: inout [String]) {
    let url = URL(fileURLWithPath: path)
    let ext = url.pathExtension.lowercased()
    guard allowedImageExtensions.contains(ext) else {
      return
    }
    guard FileManager.default.fileExists(atPath: path) else {
      return
    }
    if !paths.contains(path) {
      paths.append(path)
    }
  }

  private func readPngImage() -> FlutterStandardTypedData? {
    let pasteboard = NSPasteboard.general

    if let png = pasteboard.data(forType: .png), !png.isEmpty {
      return FlutterStandardTypedData(bytes: png)
    }

    if let tiff = pasteboard.data(forType: .tiff),
       let image = NSImage(data: tiff),
       let tiffRepresentation = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffRepresentation),
       let png = bitmap.representation(using: .png, properties: [:]),
       !png.isEmpty {
      return FlutterStandardTypedData(bytes: png)
    }

    return nil
  }
}
