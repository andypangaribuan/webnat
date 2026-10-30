import Foundation

struct BookmarkItem: Codable {
    let id: String
    var title: String
    var url: String
}

class BookmarkManager {
    private let defaultsKey: String
    private(set) var bookmarks: [BookmarkItem] = []

    init(bundleId: String) {
        self.defaultsKey = "saved_bookmarks_\(bundleId)"
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([BookmarkItem].self, from: data) else {
            bookmarks = []
            return
        }
        bookmarks = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func addBookmark(title: String, url: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty else { return }

        let finalTitle = cleanTitle.isEmpty ? cleanUrl : cleanTitle
        if let existingIdx = bookmarks.firstIndex(where: { $0.url.lowercased() == cleanUrl.lowercased() }) {
            bookmarks[existingIdx].title = finalTitle
            bookmarks[existingIdx].url = cleanUrl
        } else {
            let item = BookmarkItem(id: UUID().uuidString, title: finalTitle, url: cleanUrl)
            bookmarks.insert(item, at: 0)
        }
        save()
    }

    func removeBookmark(id: String) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func reorderBookmarks(orderedIds: [String]) {
        var map = [String: BookmarkItem]()
        for b in bookmarks {
            map[b.id] = b
        }
        var reordered = [BookmarkItem]()
        for id in orderedIds {
            if let item = map.removeValue(forKey: id) {
                reordered.append(item)
            }
        }
        // Append any remaining items (e.g., if reordered while search filter was active)
        for b in bookmarks where map[b.id] != nil {
            reordered.append(b)
        }
        bookmarks = reordered
        save()
    }

    func toPayload() -> [[String: String]] {
        return bookmarks.map {
            [
                "id": $0.id,
                "title": $0.title,
                "url": $0.url
            ]
        }
    }
}

