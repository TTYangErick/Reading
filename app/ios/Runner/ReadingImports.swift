import Flutter
import UIKit

/// Process-local, bounded file inbox. No database or reader state is touched.
final class ReadingImports: NSObject, FlutterPlugin {
  static let shared = ReadingImports()
  private final class Entry {
    let id = UUID().uuidString
    var name = "文件"
    var ready = false
    var error: String?
    var path: String?
    private let lock = NSLock()
    private var stopped = false
    var cancelled: Bool {
      get { lock.lock(); defer { lock.unlock() }; return stopped }
      set { lock.lock(); stopped = newValue; lock.unlock() }
    }
    var snapshot: [String: Any] {
      var value: [String: Any] = ["id": id, "name": name, "ready": ready]
      if let error { value["error"] = error }
      if let path { value["path"] = path }
      return value
    }
  }
  private struct ImportFailure: Error { let code: String }
  private var channel: FlutterMethodChannel?
  private var entries: [Entry] = [] // Main-thread ownership.
  private var overflow: Entry?
  private let worker = DispatchQueue(label: "dev.reading.imports")
  private let folder: URL

  private override init() {
    folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("received-books", isDirectory: true)
    super.init()
    // Serialized before copies, once per process; never touches the user library.
    worker.async { [self] in
      try? FileManager.default.removeItem(at: folder)
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = shared
    let channel = FlutterMethodChannel(name: "dev.reading/imports", binaryMessenger: registrar.messenger())
    plugin.channel = channel
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }
  private func changed() { channel?.invokeMethod("changed", arguments: nil) }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pending":
      result((entries.filter { !$0.cancelled } + [overflow].compactMap { $0 }).map { $0.snapshot })
    case "release":
      if let id = call.arguments as? String {
        if overflow?.id == id { overflow = nil }
        if let entry = entries.first(where: { $0.id == id }) {
          entry.cancelled = true
          if entry.ready {
            if let path = entry.path { try? FileManager.default.removeItem(atPath: path) }
            entries.removeAll { $0.id == id }
          }
          // In-flight copies retain their capacity until the worker exits.
        }
      }
      result(nil)
      changed()
    default: result(FlutterMethodNotImplemented)
    }
  }

  @discardableResult
  func accept(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    guard entries.count < 4 else {
      if overflow == nil {
        let entry = Entry()
        entry.name = "未接收的文件"
        entry.error = "queueFull"
        entry.ready = true
        overflow = entry
      }
      changed()
      return true
    }
    let entry = Entry()
    entry.name = String(url.lastPathComponent.unicodeScalars.filter {
      !CharacterSet.controlCharacters.contains($0)
    }.prefix(160).map(Character.init))
    entries.append(entry)
    let ext = url.pathExtension.lowercased()
    if url.lastPathComponent.unicodeScalars.count > 160 && (ext == "epub" || ext == "txt") {
      entry.name = String(entry.name.prefix(150)) + "." + ext
    }
    guard ext == "epub" || ext == "txt" else {
      entry.ready = true
      entry.error = "unsupported"
      changed()
      return true
    }
    let limit = (ext == "epub" ? 50 : 20) * 1024 * 1024
    let scoped = url.startAccessingSecurityScopedResource()
    changed()
    worker.async { [self] in
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let target = folder.appendingPathComponent(entry.id)
      var failure: Error?
      let coordinator = NSFileCoordinator()
      var coordinationError: NSError?
      coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
        do {
          if entry.cancelled { throw ImportFailure(code: "cancelled") }
          let size = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
          guard size.isRegularFile == true else { throw ImportFailure(code: "unreadable") }
          if let length = size.fileSize, length > limit { throw ImportFailure(code: "tooLarge") }
          guard let input = InputStream(url: source) else { throw ImportFailure(code: "unreadable") }
          guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
            throw ImportFailure(code: "unreadable")
          }
          let output = try FileHandle(forWritingTo: target)
          input.open()
          defer { input.close(); try? output.close() }
          var buffer = [UInt8](repeating: 0, count: 64 * 1024)
          var total = 0
          while true {
            if entry.cancelled { throw ImportFailure(code: "cancelled") }
            let count = input.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw ImportFailure(code: "unreadable") }
            if count == 0 { break }
            total += count
            if total > limit { throw ImportFailure(code: "tooLarge") }
            try output.write(contentsOf: Data(buffer.prefix(count)))
          }
        } catch { failure = error }
      }
      let error = (failure as? ImportFailure)?.code
        ?? ((failure != nil || coordinationError != nil) ? "unreadable" : nil)
      if error != nil || entry.cancelled { try? FileManager.default.removeItem(at: target) }
      DispatchQueue.main.async { [self] in
        if entry.cancelled {
          try? FileManager.default.removeItem(at: target)
          entries.removeAll { $0.id == entry.id }
        } else {
          entry.path = error == nil ? target.path : nil
          entry.error = error
          entry.ready = true
        }
        changed()
      }
    }
    return true
  }
}
