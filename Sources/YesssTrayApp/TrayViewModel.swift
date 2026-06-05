import AppKit
import Combine
import Foundation

@MainActor
final class TrayViewModel: ObservableObject {
    @Published var snapshot: TraySnapshot = .empty
    @Published var isRefreshing = false
    @Published var statusText: String = "No data yet"

    var menuBarTitle: String {
        if isRefreshing {
            return "…"
        }

        if snapshot.status == .ok, let title = snapshot.menuTitle, !title.isEmpty {
            return title
        }

        switch snapshot.status {
        case .loginRequired:
            return "Login"
        case .subscriberSelectionRequired:
            return "Select"
        case .dataUnavailable:
            return "No Data"
        case .ok:
            return "--"
        case .error:
            return "Error"
        }
    }

    func refreshNow() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        statusText = "Refreshing…"

        Task {
            do {
                let newSnapshot = try await RefreshService().refresh()
                snapshot = newSnapshot
                statusText = newSnapshot.message
            } catch {
                snapshot.status = .error
                snapshot.message = error.localizedDescription
                snapshot.menuTitle = nil
                statusText = error.localizedDescription
            }

            isRefreshing = false
        }
    }
}
