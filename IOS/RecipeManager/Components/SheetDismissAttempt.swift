import SwiftUI
import UIKit

extension View {
    /// Runs `action` when someone swipes down the sheet this view is in while its interactive dismissal is disabled
    /// (`interactiveDismissDisabled`), so the sheet can ask instead of ignoring the gesture. Works from a sheet's root
    /// and from a screen pushed inside the sheet's navigation stack. Outside a sheet it does nothing.
    func onSheetDismissAttempt(perform action: @escaping @MainActor () -> Void) -> some View {
        background(SheetDismissAttemptBridge(action: action).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

/// SwiftUI has no hook for a blocked swipe (iOS 18), so this wraps the sheet's presentation-controller delegate:
/// `presentationControllerDidAttemptToDismiss` runs the action, and every other call goes to SwiftUI's own delegate
/// unchanged (it needs `didDismiss` to reset the `isPresented` binding). The original delegate is put back when
/// this view leaves the hierarchy.
private struct SheetDismissAttemptBridge: UIViewControllerRepresentable {
    let action: @MainActor () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.action = action
        controller.install()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.uninstall() }

    final class Controller: UIViewController {
        var action: (@MainActor () -> Void)?
        private var proxy: DelegateProxy?
        private weak var installedOn: UIPresentationController?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }

        /// The sheet this view sits in: the top of the parent chain is the presented controller.
        private var sheet: UIPresentationController? {
            var top: UIViewController = self
            while let parent = top.parent { top = parent }
            return top.presentingViewController == nil ? nil : top.presentationController
        }

        /// Idempotent; also re-wraps if SwiftUI has replaced the delegate since.
        func install() {
            guard let sheet else { return }
            if let proxy, sheet.delegate === proxy { return }
            uninstall()
            let proxy = DelegateProxy(original: sheet.delegate) { [weak self] in self?.action?() }
            sheet.delegate = proxy
            self.proxy = proxy
            installedOn = sheet
        }

        func uninstall() {
            if let installedOn, let proxy, installedOn.delegate === proxy { installedOn.delegate = proxy.original }
            proxy = nil
            installedOn = nil
        }
    }

    @MainActor final class DelegateProxy: NSObject, UIAdaptivePresentationControllerDelegate {
        nonisolated(unsafe) weak var original: (any UIAdaptivePresentationControllerDelegate)?
        private let onAttempt: @MainActor () -> Void

        init(original: (any UIAdaptivePresentationControllerDelegate)?, onAttempt: @escaping @MainActor () -> Void) {
            self.original = original
            self.onAttempt = onAttempt
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            original?.presentationControllerDidAttemptToDismiss?(presentationController)
            onAttempt()
        }

        nonisolated override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
        }

        nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if let original, original.responds(to: aSelector) { return original }
            return super.forwardingTarget(for: aSelector)
        }
    }
}
