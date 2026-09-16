import Carbon
import Foundation
import SoundPloegCore

public final class CarbonHotkeyService: HotkeyService {
    private static var nextIdentifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var continuation: AsyncStream<Void>.Continuation?
    private lazy var stream: AsyncStream<Void> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
        }
    }()

    private var hotKeyID: EventHotKeyID

    public init() {
        hotKeyID = EventHotKeyID(signature: OSType(0x53504C47), id: CarbonHotkeyService.nextIdentifier)
        CarbonHotkeyService.nextIdentifier += 1
    }

    deinit {
        unregister()
    }

    public func eventStream() -> AsyncStream<Void> {
        stream
    }

    public func register(shortcut: HotkeyShortcut) throws {
        guard shortcut.carbonModifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            throw SoundPloegError.invalidHotkey
        }
        unregister()

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let instance = Unmanaged<CarbonHotkeyService>.fromOpaque(userData).takeUnretainedValue()

                var eventHotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotkeyID
                )

                if status == noErr && eventHotkeyID.id == instance.hotKeyID.id {
                    instance.continuation?.yield(())
                }

                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw SoundPloegError.hotkeyRegistrationFailed("InstallEventHandler status=\(installStatus)")
        }

        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            unregister()
            throw SoundPloegError.hotkeyRegistrationFailed("RegisterEventHotKey status=\(registerStatus)")
        }
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
