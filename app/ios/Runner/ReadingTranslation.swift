import Flutter
import SwiftUI
import Translation

// Installed models use a view-independent session on iOS 26+. Older systems
// and model consent use an attached, transparent SwiftUI child, not a modal.
// Sessions supplied by SwiftUI must stay inside their translationTask.
final class ReadingTranslation: NSObject, FlutterPlugin {
  private var registrar: FlutterPluginRegistrar?
  private var activeID: Int?
  private var reply: FlutterResult?
  private var host: UIViewController?
  private var statusTask: Task<Void, Never>?
  private var cancelTranslation: (() -> Void)?

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = ReadingTranslation()
    plugin.registrar = registrar
    let channel = FlutterMethodChannel(name: "dev.reading/translation", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = args["id"] as? Int
    if call.method == "cancel" {
      if let id, id == activeID { finish(id, error: "cancelled") }
      result(nil)
      return
    }
    guard ["status", "prepare", "translate"].contains(call.method) else {
      result(FlutterMethodNotImplemented); return
    }
    guard let id, args["from"] as? String == "en", args["to"] as? String == "zh-Hans" else {
      result(FlutterError(code: "unsupported", message: nil, details: nil)); return
    }
    #if targetEnvironment(simulator)
    result(call.method == "status" ? "unavailable" : FlutterError(code: "unavailable", message: nil, details: nil))
    return
    #else
    guard #available(iOS 18.0, *) else {
      result(call.method == "status" ? "unavailable" : FlutterError(code: "unavailable", message: nil, details: nil)); return
    }
    guard activeID == nil else {
      result(FlutterError(code: "busy", message: nil, details: nil)); return
    }
    let text = args["text"] as? String
    if call.method == "translate" && (text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false || text!.utf16.count > 4000) {
      result(FlutterError(code: "invalidText", message: nil, details: nil)); return
    }
    activeID = id
    reply = result
    statusTask = Task { @MainActor [weak self] in
      let source = Locale.Language(identifier: "en")
      let target = Locale.Language(identifier: "zh-Hans")
      let status = await LanguageAvailability().status(from: source, to: target)
      guard let self, self.activeID == id, !Task.isCancelled else { return }
      let value: String
      switch status {
      case .installed: value = "ready"
      case .supported: value = "downloadRequired"
      case .unsupported: value = "unsupported"
      @unknown default: value = "unavailable"
      }
      if call.method == "status" { self.finish(id, value: value); return }
      if value == "unsupported" || value == "unavailable" || (call.method == "translate" && value != "ready") {
        self.finish(id, error: value); return
      }
      if #available(iOS 26.0, *), call.method == "translate", let text {
        let session = TranslationSession(installedSource: source, target: target)
        self.cancelTranslation = { session.cancel() }
        do {
          let response = try await session.translate(text)
          guard !Task.isCancelled else { return }
          self.finish(id, value: response.targetText)
        } catch is CancellationError {
          self.finish(id, error: "cancelled")
        } catch {
          self.finish(id, error: "translationFailed")
        }
        return
      }
      guard var presenter = self.registrar?.viewController, presenter.viewIfLoaded?.window != nil else {
        self.finish(id, error: "unavailable"); return
      }
      while let presented = presenter.presentedViewController { presenter = presented }
      let view = TranslationWorkView(source: source, target: target,
        text: call.method == "translate" ? text : nil,
        complete: { [weak self] value, error in
          // Let the SwiftUI action return before removing its session's view.
          Task { @MainActor [weak self] in self?.finish(id, value: value, error: error) }
        })
      let host = UIHostingController(rootView: view)
      host.view.backgroundColor = .clear
      host.view.isUserInteractionEnabled = false
      host.view.accessibilityElementsHidden = true
      host.view.frame = presenter.view.bounds
      host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      self.host = host
      presenter.addChild(host)
      presenter.view.addSubview(host.view)
      host.didMove(toParent: presenter)
    }
    #endif
  }

  private func finish(_ id: Int, value: Any? = nil, error: String? = nil) {
    guard id == activeID, reply != nil else { return }
    let callback = reply
    reply = nil
    statusTask?.cancel()
    statusTask = nil
    cancelTranslation?()
    cancelTranslation = nil
    let controller = host
    host = nil
    // Dismiss only consent owned by this host, never the Flutter reader.
    // Keep busy until teardown completes, including cancellation/timeouts.
    let completed = { [weak self] in
      controller?.willMove(toParent: nil)
      controller?.view.removeFromSuperview()
      controller?.removeFromParent()
      self?.activeID = nil
      if let error { callback?(FlutterError(code: error, message: nil, details: nil)) }
      else { callback?(value) }
    }
    if let controller, controller.presentedViewController != nil {
      controller.dismiss(animated: true, completion: completed)
    }
    else { completed() }
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    if let id = activeID { finish(id, error: "cancelled") }
    self.registrar = nil
  }
}

@available(iOS 18.0, *)
private struct TranslationWorkView: View {
  let source: Locale.Language
  let target: Locale.Language
  let text: String?
  let complete: (String?, String?) -> Void

  var body: some View {
    Color.clear
    .translationTask(source: source, target: target) { session in
      do {
        if let text {
          let response = try await session.translate(text)
          complete(response.targetText, nil)
        } else {
          try await session.prepareTranslation()
          complete(nil, nil)
        }
      } catch is CancellationError {
        complete(nil, "cancelled")
      } catch {
        complete(nil, text == nil ? "downloadFailed" : "translationFailed")
      }
    }
  }
}
