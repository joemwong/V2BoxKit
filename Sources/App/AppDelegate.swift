import BackgroundTasks
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: AppConstants.backgroundRefreshIdentifier,
      using: nil
    ) { task in
      guard let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      self.handle(refreshTask)
    }
    scheduleSubscriptionRefresh()
    return true
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    scheduleSubscriptionRefresh()
  }

  private func handle(_ task: BGAppRefreshTask) {
    scheduleSubscriptionRefresh()
    let operation = Task { @MainActor in
      let store = NodeStore()
      let summary = await store.refreshAll(force: false)
      task.setTaskCompleted(success: summary.failed == 0)
    }
    task.expirationHandler = { operation.cancel() }
  }

  private func scheduleSubscriptionRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: AppConstants.backgroundRefreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      DiagnosticLogStore.shared.append(.warning, category: "subscription", message: "后台更新调度失败")
    }
  }
}
