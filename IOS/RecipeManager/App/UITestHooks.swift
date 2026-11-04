#if DEBUG
import Foundation

/// Switches for the UI tests (`RecipeManagerUITests`, run by `scripts/run-ui-tests.sh`). Debug builds only, and each
/// one does nothing unless the test passes its launch argument, so a normal run (or a release build) never sees them.
enum UITestHooks {
    private static let arguments = ProcessInfo.processInfo.arguments

    /// `-UITestReset`: start signed out with nothing saved (credentials, offline copy, queued changes, settings, caches).
    static let resets = arguments.contains("-UITestReset")

    /// `-UITestForceOffline`: behave as if the server can't be reached for this whole launch (`Connectivity.isOffline`).
    static let forcesOffline = arguments.contains("-UITestForceOffline")

    /// Runs before `Session` is made (see `AppServices.session`), so nothing has read the old state yet.
    static func resetIfAsked() {
        guard resets else { return }
        CredentialStore.delete()
        let files = FileManager.default
        for place in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory] {
            guard let dir = files.urls(for: place, in: .userDomainMask).first,
                  let contents = try? files.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in contents { try? files.removeItem(at: item) }
        }
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        WidgetBridge.clear()
    }
}
#endif
