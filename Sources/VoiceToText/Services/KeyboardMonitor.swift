import CoreGraphics
import Foundation

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handleEvent(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

final class KeyboardMonitor {

    var onFnKeyDown: (() -> Void)?
    var onFnKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var monitorRunLoop: CFRunLoop?
    private var monitorThread: Thread?
    private var isFnPressed = false

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else { return }

        let thread = Thread { [weak self] in
            guard let self else { return }
            self.setupEventTap()
        }
        thread.name = "com.voicetotext.keyboardmonitor"
        thread.qualityOfService = .userInteractive
        monitorThread = thread
        thread.start()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let rl = monitorRunLoop {
            CFRunLoopStop(rl)
        }
        eventTap = nil
        monitorRunLoop = nil
        monitorThread = nil
    }

    private func setupEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            print("[KeyboardMonitor] Failed to create event tap — accessibility permission required")
            return
        }

        eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            print("[KeyboardMonitor] Failed to create run loop source")
            return
        }

        let rl = CFRunLoopGetCurrent()!
        monitorRunLoop = rl
        CFRunLoopAddSource(rl, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let flags = event.flags
        let fnNowPressed = flags.contains(.maskSecondaryFn)

        if fnNowPressed && !isFnPressed {
            let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
            if flags.intersection(otherModifiers).isEmpty {
                isFnPressed = true
                onFnKeyDown?()
            }
        } else if !fnNowPressed && isFnPressed {
            isFnPressed = false
            onFnKeyUp?()
        }
    }
}
