package soonlnk.features

import soonlnk.commons.*
import std.collection.{ArrayList, HashMap}
import std.sync.Mutex

public class FavoritesFeature {
    let store: FavoriteStore
    let mutex: Mutex = Mutex()
    var cache: ArrayList<FavoriteEntry> = ArrayList<FavoriteEntry>()

    public init(store: FavoriteStore) {
        this.store = store
        this.cache = sanitizeFavorites(store.load())
    }

    public func mode(): String {
        store.mode()
    }

    public func list(): ArrayList<FavoriteEntry> {
        let out = ArrayList<FavoriteEntry>()
        synchronized(mutex) {
            for (entry in cache) {
                out.add(entry)
            }
        }
        out
    }

    public func replace(entries: ArrayList<FavoriteEntry>): ArrayList<FavoriteEntry> {
        let cleaned = sanitizeFavorites(entries)
        synchronized(mutex) {
            cache = cleaned
            store.save(cache)
        }
        list()
    }
}

func sanitizeFavorites(entries: ArrayList<FavoriteEntry>): ArrayList<FavoriteEntry> {
    let out = ArrayList<FavoriteEntry>()
    let dedup = HashMap<String, Bool>()
    for (entry in entries) {
        if (entry.deviceId.size == 0 || entry.path.size == 0) {
            continue
        }
        let normalizedPath = normalizeFavoritePath(entry.path)
        let key = "${entry.deviceId}::${normalizedPath}"
        if ((dedup.get(key) ?? false)) {
            continue
        }
        dedup.add(key, true)

        let next = FavoriteEntry()
        next.deviceId = entry.deviceId
        next.path = normalizedPath
        next.name = if (entry.name.size > 0) { entry.name } else { "${entry.deviceId}: ${normalizedPath}" }
        next.createdAt = if (entry.createdAt > 0) { entry.createdAt } else { currentTimestamp() }
        out.add(next)
    }
    out
}

func normalizeFavoritePath(path: String): String {
    var out = path.trimAscii()
    if (out.size == 0) {
        return "/"
    }
    if (!strStartsWith(out, "/")) {
        out = "/" + out
    }
    while (strContains(out, "//")) {
        out = strReplace(out, "//", "/")
    }
    if (out.size > 1 && strEndsWith(out, "/")) {
        out = strSubstring(out, 0, out.size - 1)
    }
    out
}
