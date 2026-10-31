import Foundation
import SwiftUI

private enum VaultKeys {
    static let bookmark = "poka.vault.bookmark"
    static let pathDisplay = "poka.vault.pathDisplay"
}

@MainActor
@Observable
final class VaultService {
    private(set) var rootURL: URL?
    private(set) var displayPath: String?
    var errorMessage: String?

    var hasVault: Bool { rootURL != nil }

    init() {
        restoreBookmark()
    }

    func clearVault() {
        rootURL = nil
        displayPath = nil
        UserDefaults.standard.removeObject(forKey: VaultKeys.bookmark)
        UserDefaults.standard.removeObject(forKey: VaultKeys.pathDisplay)
    }

    func adoptURL(_ url: URL) {
        errorMessage = nil
        do {
            let bookmark = try url.bookmarkData(
                options: bookmarkOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: VaultKeys.bookmark)
            UserDefaults.standard.set(url.path, forKey: VaultKeys.pathDisplay)
            rootURL = try resolveBookmark(bookmark)
            displayPath = url.path
        } catch {
            errorMessage = "Could not access this folder: \(error.localizedDescription)"
        }
    }

    func startAccessingVault() -> URL? {
        guard let url = rootURL else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    func stopAccessingVault() {
        rootURL?.stopAccessingSecurityScopedResource()
    }

    private func restoreBookmark() {
        guard let bookmark = UserDefaults.standard.data(forKey: VaultKeys.bookmark) else { return }
        displayPath = UserDefaults.standard.string(forKey: VaultKeys.pathDisplay)
        rootURL = try? resolveBookmark(bookmark)
    }

    private func resolveBookmark(_ data: Data) throws -> URL {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            let refreshed = try url.bookmarkData(
                options: bookmarkOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(refreshed, forKey: VaultKeys.bookmark)
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw VaultError.accessDenied
        }
        return url
    }

    private var bookmarkOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }
}

enum VaultError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Poka does not have permission to read this folder."
        }
    }
}
