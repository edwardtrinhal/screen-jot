import AppKit

/// Asks GitHub for the latest release and compares it with the running version.
/// No auto-install: a newer version is offered as a download of the DMG.
enum UpdateChecker {
    static let repo = "edwardtrinhal/screen-jot"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    enum Result {
        case upToDate
        case available(version: String, download: URL)
        case failed(String)
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func check() async -> Result {
        var request = URLRequest(url: latestAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ScreenJot/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("GitHub returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                return .failed("Unexpected response from GitHub.")
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard isVersion(latest, newerThan: currentVersion) else { return .upToDate }
            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmg = assets.first { ($0["name"] as? String) == "ScreenJot.dmg" }
            let download = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
                ?? (json["html_url"] as? String).flatMap(URL.init(string:))
                ?? releasesPage
            return .available(version: latest, download: download)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Numeric dotted compare: "0.1.10" > "0.1.9", "1.0" == "1.0.0".
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Runs a check and reports the outcome in an alert; a newer version gets a Download button.
    @MainActor
    static func checkAndPresent() async {
        let result = await check()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        switch result {
        case .upToDate:
            alert.messageText = "You're up to date"
            alert.informativeText = "ScreenJot \(currentVersion) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        case .available(let version, let download):
            alert.messageText = "ScreenJot \(version) is available"
            alert.informativeText = "You have \(currentVersion). Download the new DMG, quit ScreenJot, and drag the new app over the old one in Applications."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(download) }
        case .failed(let message):
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Releases Page")
            if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(releasesPage) }
        }
    }
}
