import Combine
import Foundation

enum VersionCheckStatus: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(currentVersion: String, latestVersion: String, releaseURL: URL)
    case failed(message: String)
}

@MainActor
final class AppVersionChecker: ObservableObject {
    @Published private(set) var status: VersionCheckStatus = .idle

    let currentVersion: String

    private let latestReleaseAPIURL: URL
    private let latestReleaseWebURL: URL
    private let session: URLSession

    init(
        currentVersion: String = AppVersionChecker.bundleShortVersion(),
        latestReleaseAPIURL: URL = URL(string: "https://api.github.com/repos/ximendatie/mahjong/releases/latest")!,
        latestReleaseWebURL: URL = URL(string: "https://github.com/ximendatie/mahjong/releases/latest")!,
        session: URLSession = .shared
    ) {
        self.currentVersion = currentVersion
        self.latestReleaseAPIURL = latestReleaseAPIURL
        self.latestReleaseWebURL = latestReleaseWebURL
        self.session = session
    }

    func checkForUpdates() {
        status = .checking

        Task {
            do {
                let latestRelease = try await fetchLatestRelease()
                let latestVersion = Self.normalizedVersion(latestRelease.tagName)

                if Self.compareVersions(latestVersion, currentVersion) == .orderedDescending {
                    status = .updateAvailable(
                        currentVersion: currentVersion,
                        latestVersion: latestVersion,
                        releaseURL: latestRelease.htmlURL
                    )
                } else {
                    status = .upToDate(version: currentVersion)
                }
            } catch let error as VersionCheckError {
                status = .failed(message: error.message)
            } catch {
                status = .failed(message: "无法检查更新，请稍后重试，或直接打开 GitHub Releases。")
            }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubLatestRelease {
        do {
            return try await fetchLatestReleaseFromAPI()
        } catch {
            return try await fetchLatestReleaseFromRedirect()
        }
    }

    private func fetchLatestReleaseFromAPI() async throws -> GitHubLatestRelease {
        var request = URLRequest(url: latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("mahjong", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
    }

    private func fetchLatestReleaseFromRedirect() async throws -> GitHubLatestRelease {
        var request = URLRequest(url: latestReleaseWebURL)
        request.setValue("mahjong", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<400).contains(httpResponse.statusCode),
              let finalURL = httpResponse.url,
              let tagName = Self.releaseTagName(from: finalURL)
        else {
            throw VersionCheckError.unavailable
        }

        return GitHubLatestRelease(tagName: tagName, htmlURL: finalURL)
    }

    nonisolated static func bundleShortVersion(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    nonisolated static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
    }

    nonisolated static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = versionParts(lhs)
        let rhsParts = versionParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let lhsValue = index < lhsParts.count ? lhsParts[index] : 0
            let rhsValue = index < rhsParts.count ? rhsParts[index] : 0

            if lhsValue < rhsValue {
                return .orderedAscending
            }
            if lhsValue > rhsValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    nonisolated static func releaseTagName(from url: URL) -> String? {
        let components = url.pathComponents
        guard let tagIndex = components.firstIndex(of: "tag"),
              components.indices.contains(tagIndex + 1)
        else {
            return nil
        }

        return components[tagIndex + 1]
    }

    private nonisolated static func versionParts(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: ".")
            .map { component in
                let digits = component.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}

private struct GitHubLatestRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private enum VersionCheckError: Error {
    case unavailable

    var message: String {
        switch self {
        case .unavailable:
            "无法检查更新，请稍后重试，或直接打开 GitHub Releases。"
        }
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }

        return String(dropFirst(prefix.count))
    }
}
