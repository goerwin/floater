import AppKit
import ApplicationServices

@MainActor
final class AccessibilityWaiter {
    private var observer: AXObserver?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var deadline: Task<Void, Never>?
    private var isReady: () -> Bool = { false }

    func wait(
        processID: pid_t, elements: [AXUIElement],
        notifications: [String], isReady: @escaping () -> Bool,
        perform: () -> Void
    ) async -> Bool {
        self.isReady = isReady
        AXObserverCreate(processID, { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let waiter = Unmanaged<AccessibilityWaiter>.fromOpaque(context).takeUnretainedValue()
                waiter.check()
            }
        }, &observer)
        if let observer {
            let context = Unmanaged.passUnretained(self).toOpaque()
            for element in elements {
                for notification in notifications {
                    AXObserverAddNotification(observer, element, notification as CFString, context)
                }
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        defer {
            if let observer {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            observer = nil
            self.isReady = { false }
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(false); return }
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    self?.finish(false)
                }
                perform()
                check()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(false) }
        }
    }

    private func check() {
        if isReady() { finish(true) }
    }

    private func finish(_ ready: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        continuation.resume(returning: ready)
    }
}
