package soonlnk.tests

import soonlnk.commons.*
import soonlnk.features.*
import std.collection.ArrayList
import std.fs.remove
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class FavoritesFeature_test {
    @TestCase
    public func cacheModeReplaceAndList(): Unit {
        let feature = FavoritesFeature(MemoryFavoriteStore())
        let input = ArrayList<FavoriteEntry>()

        let entry = FavoriteEntry()
        entry.deviceId = "local"
        entry.path = "/docs"
        entry.name = "docs"
        input.add(entry)

        let updated = feature.replace(input)
        @Assert(feature.mode(), "cache")
        @Assert(updated.size, 1)
        @Assert(updated[0].deviceId, "local")
        @Assert(updated[0].path, "/docs")
    }

    @TestCase
    public func tomlStorePersists(): Unit {
        let path = testTempPath("soonlink_favorites") + ".toml"
        let feature = FavoritesFeature(TomlFavoriteStore(path))
        let input = ArrayList<FavoriteEntry>()

        let entry = FavoriteEntry()
        entry.deviceId = "node-1"
        entry.path = "/media"
        entry.name = "media"
        input.add(entry)
        feature.replace(input)

        let reloaded = FavoritesFeature(TomlFavoriteStore(path))
        let list = reloaded.list()
        @Assert(reloaded.mode(), "toml")
        @Assert(list.size, 1)
        @Assert(list[0].deviceId, "node-1")
        @Assert(list[0].path, "/media")

        remove(path)
    }
}
