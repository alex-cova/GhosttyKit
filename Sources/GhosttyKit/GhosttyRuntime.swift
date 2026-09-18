import AppKit
import Foundation

#if GHOSTTYKIT_HAS_KIT
import GhosttyKitC
#endif

/// Process-wide libghostty runtime. One `ghostty_app_t` is shared by every
/// `GhosttyView` in the process.
@MainActor
public final class GhosttyRuntime {
    public static let shared = GhosttyRuntime()

    /// True when this build of GhosttyKit was linked against libghostty.
    public nonisolated static var isAvailable: Bool {
        #if GHOSTTYKIT_HAS_KIT
        true
        #else
        false
        #endif
    }

    public private(set) var isRunning = false

    #if GHOSTTYKIT_HAS_KIT
    private var app: ghostty_app_t?
    private var config: ghostty_config_t?
    #endif

    fileprivate var surfaces: [ObjectIdentifier: GhosttySurfaceView] = [:]

    private init() {}

    public func start() throws {
        #if GHOSTTYKIT_HAS_KIT
        if isRunning { return }

        let initStatus = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        if initStatus != GHOSTTY_SUCCESS {
            throw GhosttyError.runtimeFailed("ghostty_init failed with status \(initStatus).")
        }

        let cfg = ghostty_config_new()
        guard let cfg else {
            throw GhosttyError.runtimeFailed("ghostty_config_new failed.")
        }
        ghostty_config_load_default_files(cfg)
        ghostty_config_finalize(cfg)
        config = cfg

        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: ghosttyWakeup,
            action_cb: ghosttyAction,
            read_clipboard_cb: ghosttyReadClipboard,
            confirm_read_clipboard_cb: ghosttyConfirmReadClipboard,
            write_clipboard_cb: ghosttyWriteClipboard,
            close_surface_cb: ghosttyCloseSurface
        )

        guard let created = ghostty_app_new(&runtime, cfg) else {
            ghostty_config_free(cfg)
            config = nil
            throw GhosttyError.runtimeFailed("ghostty_app_new failed.")
        }
        app = created
        isRunning = true
        applyColorScheme()
        #else
        throw GhosttyError.kitMissing
        #endif
    }

    func tick() {
        #if GHOSTTYKIT_HAS_KIT
        guard let app else { return }
        ghostty_app_tick(app)
        #endif
    }

    #if GHOSTTYKIT_HAS_KIT
    func makeSurface(
        view: GhosttySurfaceView,
        configuration: GhosttySurfaceConfiguration
    ) throws -> ghostty_surface_t {
        try start()
        guard let app else { throw GhosttyError.runtimeFailed("Ghostty app is not running.") }

        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let surface = configuration.withCValue(view: view, scale: scale) { cfg in
            ghostty_surface_new(app, &cfg)
        }
        guard let surface else { throw GhosttyError.surfaceFailed }
        surfaces[ObjectIdentifier(view)] = view
        return surface
    }

    func forgetSurface(_ view: GhosttySurfaceView) {
        surfaces.removeValue(forKey: ObjectIdentifier(view))
    }

    func surfaceView(for surface: ghostty_surface_t) -> GhosttySurfaceView? {
        guard let userdata = ghostty_surface_userdata(surface) else { return nil }
        return Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    func applyColorScheme() {
        guard let app else { return }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ghostty_app_set_color_scheme(app, dark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)
    }
    #endif
}

#if GHOSTTYKIT_HAS_KIT

extension GhosttySurfaceConfiguration {
    func withCValue<T>(view: NSView, scale: Double, _ body: (inout ghostty_surface_config_s) -> T) -> T {
        func run(cwd: UnsafePointer<CChar>?, cmd: UnsafePointer<CChar>?, input: UnsafePointer<CChar>?) -> T {
            var cfg = ghostty_surface_config_new()
            cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
            cfg.platform.macos.nsview = Unmanaged.passUnretained(view).toOpaque()
            cfg.userdata = Unmanaged.passUnretained(view).toOpaque()
            cfg.scale_factor = scale
            cfg.font_size = Float(fontSize)
            cfg.working_directory = cwd
            cfg.command = cmd
            cfg.initial_input = input
            cfg.wait_after_command = waitAfterCommand
            cfg.context = GHOSTTY_SURFACE_CONTEXT_TAB
            return body(&cfg)
        }

        return workingDirectory?.path.withCString { cwd in
            if let command {
                return command.withCString { cmd in
                    if let initialInput {
                        return initialInput.withCString { input in
                            run(cwd: cwd, cmd: cmd, input: input)
                        }
                    }
                    return run(cwd: cwd, cmd: cmd, input: nil)
                }
            }
            if let initialInput {
                return initialInput.withCString { input in
                    run(cwd: cwd, cmd: nil, input: input)
                }
            }
            return run(cwd: cwd, cmd: nil, input: nil)
        } ?? {
            if let command {
                return command.withCString { cmd in
                    if let initialInput {
                        return initialInput.withCString { input in
                            run(cwd: nil, cmd: cmd, input: input)
                        }
                    }
                    return run(cwd: nil, cmd: cmd, input: nil)
                }
            }
            if let initialInput {
                return initialInput.withCString { input in
                    run(cwd: nil, cmd: nil, input: input)
                }
            }
            return run(cwd: nil, cmd: nil, input: nil)
        }()
    }
}

private func ghosttyWakeup(_ userdata: UnsafeMutableRawPointer?) {
    guard let userdata else { return }
    nonisolated(unsafe) let captured = userdata
    DispatchQueue.main.async {
        let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(captured).takeUnretainedValue()
        runtime.tick()
    }
}

private func ghosttyAction(
    _ app: ghostty_app_t?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    _ = app
    return MainActor.assumeIsolated {
        GhosttyActionRouter.handle(target: target, action: action)
    }
}

private func ghosttyCloseSurface(_ userdata: UnsafeMutableRawPointer?, _ processAlive: Bool) {
    guard let userdata else { return }
    let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    view.session?.onClose?(processAlive)
    view.session?.isProcessRunning = false
}

private func ghosttyReadClipboard(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?,
    _ mimes: UnsafePointer<UnsafePointer<CChar>?>?,
    _ mimesLen: Int,
    _ list: Bool
) -> ghostty_clipboard_read_result_e {
    guard let userdata else { return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED }
    let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    return view.completeClipboardRead(
        location: location,
        state: state,
        mimes: mimes,
        mimesLen: mimesLen,
        list: list
    )
}

private func ghosttyConfirmReadClipboard(
    _ userdata: UnsafeMutableRawPointer?,
    _ confirm: UnsafePointer<ghostty_clipboard_confirm_s>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
    _ = request
    guard let userdata else { return }
    let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    view.denyClipboard(state: state)
}

private func ghosttyWriteClipboard(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ len: Int,
    _ confirm: Bool
) {
    guard let userdata else { return }
    let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    view.writeClipboard(location: location, content: content, len: len, confirm: confirm)
}

enum GhosttyActionRouter {
    static func handle(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        let view: GhosttySurfaceView? = {
            guard target.tag == GHOSTTY_TARGET_SURFACE else { return nil }
            return GhosttyRuntime.shared.surfaceView(for: target.target.surface)
        }()

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            if let title = action.action.set_title.title {
                view?.session?.title = String(cString: title)
            }
            return true
        case GHOSTTY_ACTION_PWD:
            if let pwd = action.action.pwd.pwd {
                let path = String(cString: pwd)
                view?.session?.currentDirectory = URL(fileURLWithPath: path)
            }
            return true
        case GHOSTTY_ACTION_MOUSE_SHAPE:
            view?.applyMouseShape(action.action.mouse_shape.rawValue)
            return true
        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            view?.isMouseHidden = action.action.mouse_visibility == GHOSTTY_MOUSE_HIDDEN
            view?.window?.invalidateCursorRects(for: view ?? NSView())
            return true
        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
            let payload = action.action.mouse_over_link
            if payload.len > 0, let url = payload.url {
                view?.session?.hoveredLink = String(bytes: UnsafeBufferPointer(start: url, count: payload.len).map { UInt8(bitPattern: $0) }, encoding: .utf8)
            } else {
                view?.session?.hoveredLink = nil
            }
            return true
        case GHOSTTY_ACTION_OPEN_URL:
            let payload = action.action.open_url
            if payload.len > 0, let urlPtr = payload.url {
                let value = String(cString: urlPtr)
                if let onOpen = view?.session?.onOpenURL, case .allow(let url) = GhosttyURLPolicy.decide(value) {
                    onOpen(url)
                } else {
                    _ = GhosttyURLPolicy.open(value)
                }
            }
            return true
        case GHOSTTY_ACTION_RING_BELL:
            view?.session?.bellCount += 1
            view?.session?.onBell?()
            return true
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            view?.session?.isProcessRunning = false
            view?.session?.exitCode = Int32(action.action.child_exited.exit_code)
            return true
        case GHOSTTY_ACTION_NEW_TAB:
            view?.session?.onRequestNewTab?()
            return view?.session?.onRequestNewTab != nil
        case GHOSTTY_ACTION_NEW_WINDOW:
            view?.session?.onRequestNewWindow?()
            return view?.session?.onRequestNewWindow != nil
        case GHOSTTY_ACTION_RENDER:
            view?.needsDisplay = true
            return true
        default:
            // Window chrome, splits, GTK inspector, etc. belong to the host.
            return false
        }
    }
}
#endif
