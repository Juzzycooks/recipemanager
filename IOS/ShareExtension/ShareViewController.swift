import SwiftUI
import UIKit

/// Entry point of the "Save to Recipes" share extension: hosts the SwiftUI screen.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(items: (extensionContext?.inputItems as? [NSExtensionItem]) ?? [])
        let root = ShareView(model: model,
                             finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
                             cancel: { [weak self] in
                                 self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
                             })
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
