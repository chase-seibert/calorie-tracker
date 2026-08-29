import Combine
import UIKit

struct HomeScreenQuickActionRequest: Equatable, Identifiable {
    let id = UUID()
    let selectionID: String
}

@MainActor
final class HomeScreenQuickActionRouter: ObservableObject {
    static let shared = HomeScreenQuickActionRouter()

    @Published private(set) var request: HomeScreenQuickActionRequest?

    private init() {}

    func receive(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard
            shortcutItem.type == HomeScreenQuickActions.type,
            let selectionID = shortcutItem.userInfo?[HomeScreenQuickActions.selectionIDKey] as? String
        else { return false }
        request = HomeScreenQuickActionRequest(selectionID: selectionID)
        return true
    }

    func consume(_ request: HomeScreenQuickActionRequest) {
        guard self.request?.id == request.id else { return }
        self.request = nil
    }
}

@MainActor
enum HomeScreenQuickActions {
    static let type = "com.cseibert.CalorieTracker.log-magic"
    static let selectionIDKey = "selectionID"

    static func update(document: DiaryDocument, at date: Date = Date()) {
        let selections = QuickLogSnapshot(document: document).magicSelections(at: date)
        UIApplication.shared.shortcutItems = selections.map { selection in
            UIApplicationShortcutItem(
                type: type,
                localizedTitle: selection.title,
                localizedSubtitle: selection.subtitle,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.circle.fill"),
                userInfo: [selectionIDKey: selection.id as NSString]
            )
        }
    }
}

final class VitaChaseAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            Task { @MainActor in
                _ = HomeScreenQuickActionRouter.shared.receive(shortcutItem)
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = VitaChaseSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            completionHandler(HomeScreenQuickActionRouter.shared.receive(shortcutItem))
        }
    }
}

final class VitaChaseSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        Task { @MainActor in
            _ = HomeScreenQuickActionRouter.shared.receive(shortcutItem)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            completionHandler(HomeScreenQuickActionRouter.shared.receive(shortcutItem))
        }
    }
}
