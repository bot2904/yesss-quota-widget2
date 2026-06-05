import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TrayViewModel

    @State private var login: String = SettingsStore.login
    @State private var password: String = KeychainStore().readPassword(service: SettingsStore.keychainService, account: SettingsStore.keychainAccountPassword) ?? ""
    @State private var subscriber: String = SettingsStore.subscriberOverride ?? ""
    @State private var refreshIntervalSeconds: Int = AppConfig.refreshIntervalSeconds
    @State private var message: String = ""
    @State private var messageIsSuccess = false
    @State private var isCheckingCredentials = false
    @State private var isRefreshing = false

    let onRefreshRequested: () -> Void
    let onRefreshIntervalChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YESSS Settings")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Login")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Phone number or login", text: $login)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)

                Text("Password")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)

                Text("Subscriber ID (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Leave empty for current/default line", text: $subscriber)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Credentials are stored in your macOS Keychain. The app refreshes YESSS directly and does not write quota snapshots to disk.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Refresh")
                    .font(.headline)

                Picker("Auto-refresh", selection: $refreshIntervalSeconds) {
                    ForEach(AppConfig.refreshIntervalOptions, id: \.seconds) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: refreshIntervalSeconds) { newValue in
                    AppConfig.setRefreshIntervalSeconds(newValue)
                    onRefreshIntervalChanged()
                }
            }

            Divider()

            accountSection

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(messageIsSuccess ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Clear") {
                    SettingsStore.clearCredentials()
                    login = ""
                    password = ""
                    subscriber = ""
                    setMessage("Credentials cleared.", success: false)
                }

                Spacer()

                Button {
                    checkCredentials()
                } label: {
                    if isCheckingCredentials {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check")
                    }
                }
                .disabled(isCheckingCredentials || login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)

                Button {
                    save()
                    isRefreshing = true
                    onRefreshRequested()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save & Refresh")
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current Account")
                .font(.headline)

            let account = viewModel.snapshot.account
            if let label = account.currentLabel, !label.isEmpty {
                settingRow(label: "Line", value: label)
            } else {
                settingRow(label: "Line", value: "Unknown")
            }

            if let currentSubscriber = account.currentSubscriber, !currentSubscriber.isEmpty {
                settingRow(label: "Subscriber", value: currentSubscriber)
            }

            let savedLogin = SettingsStore.login
            if !savedLogin.isEmpty {
                settingRow(label: "Login", value: savedLogin)
            }

            if let configuredSubscriber = SettingsStore.subscriberOverride {
                settingRow(label: "Configured subscriber", value: configuredSubscriber)
            }

            if account.requiresSubscriberSelection {
                Text("Subscriber selection is required. Enter one of the linked subscriber IDs above and refresh.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 135, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func save() {
        do {
            try SettingsStore.save(
                login: login,
                password: password,
                subscriber: subscriber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subscriber
            )
            setMessage("Saved to Keychain.", success: true)
        } catch {
            setMessage(error.localizedDescription, success: false)
        }
    }

    private func checkCredentials() {
        isCheckingCredentials = true
        setMessage("Checking credentials…", success: false)
        let username = login
        let passwordValue = password

        Task {
            let result: YesssCredentialCheckResult
            do {
                result = try await YesssClient(timeout: AppConfig.refreshTimeoutSeconds)
                    .checkCredentials(login: username, password: passwordValue)
            } catch {
                result = YesssCredentialCheckResult(isValid: false, message: "Could not start credential check: \(error.localizedDescription)")
            }

            await MainActor.run {
                isCheckingCredentials = false
                setMessage(result.message, success: result.isValid)
            }
        }
    }

    private func setMessage(_ value: String, success: Bool) {
        message = value
        messageIsSuccess = success
    }
}
