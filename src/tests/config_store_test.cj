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
        let args = [
            "soonlink",
            "--config=${path}",
            "--port=9092",
            "--root-dir=${root}",
            "--favorites-mode=toml",
            "--advertise-ip=192.168.10.8",
            "--disable-discovery-broadcast"
        ]

        let config = loadAppConfig(args)

        @Assert(config.configFile, path)
        @Assert(config.webPort, 9092)
        @Assert(config.localRootDir, root)
        @Assert(config.favoritesStoreMode, "toml")
        @Assert(config.discoveryAdvertiseIp, "192.168.10.8")
        @Assert(!config.discoveryBroadcastEnabled)
        @Assert(config.nodeId.size > 0)

        let loaded = TomlConfigStore(path).load()
        @Assert(loaded.get("node_id") ?? "", config.nodeId)
        @Assert(loaded.get("local_root_dir") ?? "", root)
        @Assert(loaded.get("favorites_store_mode") ?? "", "toml")
        @Assert(loaded.get("discovery_advertise_ip") ?? "", "192.168.10.8")
        @Assert(loaded.get("discovery_broadcast_enabled") ?? "", "false")

        remove(path)
    }

    @TestCase
    public func loadAppConfigLetsArgsOverrideDiscoveryTomlSettings(): Unit {
        let scope = testTempToken("soonlink_discovery_override")
        let path = "/tmp/${scope}.toml"
        let store = TomlConfigStore(path)
        let inMap = HashMap<String, String>()
        inMap.add("discovery_advertise_ip", "192.168.10.3")
        inMap.add("discovery_broadcast_enabled", "true")
        store.save(inMap)

        let config = loadAppConfig([
            "soonlink",
            "--config=${path}",
            "--advertise-ip=192.168.10.9",
            "--disable-discovery-broadcast"
        ])

        @Assert(config.discoveryAdvertiseIp, "192.168.10.9")
        @Assert(!config.discoveryBroadcastEnabled)

        remove(path)
    }

    @TestCase
    public func loadAppConfigDerivesStableNodeIdWhenTomlOmitsIt(): Unit {
        let scope = testTempToken("soonlink_node_id")
        let path = "/tmp/${scope}.toml"
        let store = TomlConfigStore(path)
        let inMap = HashMap<String, String>()
        inMap.add("web_port", "19081")
        inMap.add("local_root_dir", "/tmp/${scope}_root")
        store.save(inMap)

        let first = loadAppConfig(["soonlink", "--config=${path}"])
        let second = loadAppConfig(["soonlink", "--config=${path}"])

        @Assert(first.nodeId.size > 0)
        @Assert(first.nodeId, second.nodeId)

        remove(path)
    }
}
