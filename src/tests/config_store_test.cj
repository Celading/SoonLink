package soonlnk.tests

import soonlnk.commons.*
import soonlnk.features.*
import soonlnk.master.*
import soonlnk.product.*
import std.collection.HashMap
import std.fs.remove
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class ConfigStore_test {
    @TestCase
    public func saveAndLoadToml(): Unit {
        let path = testTempPath("soonlink_config") + ".toml"
        let store = TomlConfigStore(path)

        let inMap = HashMap<String, String>()
        inMap.add("temp_dir", "/tmp/soonlink-case")
        inMap.add("security_mode", "encrypted")
        inMap.add("max_connections", "88")

        store.save(inMap)
        let outMap = store.load()

        @Assert(outMap.get("temp_dir") ?? "", "/tmp/soonlink-case")
        @Assert(outMap.get("security_mode") ?? "", "encrypted")
        @Assert(outMap.get("max_connections") ?? "", "88")

        remove(path)
    }

    @TestCase
    public func loadAppConfigCreatesTomlAndAppliesArgs(): Unit {
        let scope = testTempToken("soonlink_bootstrap")
        let path = "/tmp/${scope}.toml"
        let root = "/tmp/${scope}_root"
        let args = ["soonlink", "--config=${path}", "--port=9092", "--root-dir=${root}", "--favorites-mode=toml"]

        let config = loadAppConfig(args)

        @Assert(config.configFile, path)
        @Assert(config.webPort, 9092)
        @Assert(config.localRootDir, root)
        @Assert(config.favoritesStoreMode, "toml")

        let loaded = TomlConfigStore(path).load()
        @Assert(loaded.get("local_root_dir") ?? "", root)
        @Assert(loaded.get("favorites_store_mode") ?? "", "toml")

        remove(path)
    }
}
