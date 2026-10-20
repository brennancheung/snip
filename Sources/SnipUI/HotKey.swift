import Carbon.HIToolbox

/// A system-wide keyboard shortcut through Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility permission. Several can be registered at once. Each stays registered until
/// `unregister()` is called or it is released.
@MainActor
public final class HotKey {
    public struct RegistrationError: Error, CustomStringConvertible {
        public let status: OSStatus

        public var description: String {
            status == OSStatus(eventHotKeyExistsErr)
                ? "Another app already uses this shortcut."
                : "Couldn't register the shortcut (error \(status))."
        }
    }

    private static var nextID: UInt32 = 1
    private static var registered: [UInt32: WeakHotKey] = [:]
    private static var handlerInstalled = false

    private let id: UInt32
    private let handler: @MainActor () -> Void
    nonisolated(unsafe) private var ref: EventHotKeyRef?

    /// `keyCode` is a virtual key code (`kVK_ANSI_6`), `carbonModifiers` a mask of `cmdKey`,
    /// `shiftKey`, `optionKey` and `controlKey`. Throws if another app holds the same shortcut.
    public init(keyCode: UInt32, carbonModifiers: UInt32, handler: @escaping @MainActor () -> Void) throws {
        try Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        self.handler = handler

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
        let status = RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, let hotKeyRef else { throw RegistrationError(status: status) }
        ref = hotKeyRef
        Self.registered[id] = WeakHotKey(hotKey: self)
    }

    public func unregister() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        Self.registered[id] = nil
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }

    /// One handler on the application target serves every HotKey; it routes by the hot key's id.
    private static func installHandlerIfNeeded() throws {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
        guard status == noErr else { throw RegistrationError(status: status) }
        handlerInstalled = true
    }

    fileprivate static func fire(id: UInt32) {
        registered[id]?.hotKey?.handler()
    }
}

private struct WeakHotKey {
    weak var hotKey: HotKey?
}

/// "Snip", so the handler ignores hot keys registered by anything else in the process.
private let hotKeySignature: OSType = 0x536E_6970

private func hotKeyEventHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    let id = hotKeyID.id
    // Carbon delivers application-target events on the main thread.
    MainActor.assumeIsolated { HotKey.fire(id: id) }
    return noErr
}
