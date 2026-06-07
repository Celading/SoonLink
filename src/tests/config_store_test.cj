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
    public func saveAndLoadYamlUserConfig(): Unit {
        let path = testTempPath("soonlink_config") + ".yaml"
        let store = configStoreFor(path)

        let inMap = HashMap<String, String>()
        inMap.add("web_port", "19081")
        inMap.add("local_root_dir", "/tmp/soonlink-yaml")

        store.save(inMap)
        let outMap = store.load()

        @Assert(outMap.get("web_port") ?? "", "19081")
        @Assert(outMap.get("local_root_dir") ?? "", "/tmp/soonlink-yaml")

        remove(path)
    }

    @TestCase
    public func defaultConfigPathUsesSoonlinkUserEntry(): Unit {
        @Assert(strEndsWith(defaultSoonLinkConfigFile(), "/.soonlink/etc/sl-config.yaml"))
        @Assert(fallbackSoonLinkConfigFile(), "./config/soonlink.toml")
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

    @TestCase
    public func loadAppConfigReadsCliLikeTomlOptionsAndLetsArgsOverride(): Unit {
        let scope = testTempToken("soonlink_toml_alias")
        let path = "/tmp/${scope}.toml"
        let root = "/tmp/${scope}_from_toml"
        let fileMgr = LocalFileMgr()
        fileMgr.writeText(
            path,
            "[soonlink]\n" +
            "port = \"19091\"\n" +
            "root-dir = \"${root}\"\n" +
            "favorites-mode = \"toml\"\n" +
            "trust-proxy-headers = \"true\"\n" +
            "enable-mdns = \"false\"\n",
            false
        )

        let config = loadAppConfig(["soonlink", "--config=${path}", "--port=19092"])

        @Assert(config.webPort, 19092)
        @Assert(config.localRootDir, root)
        @Assert(config.favoritesStoreMode, "toml")
        @Assert(config.localAuthTrustProxyHeaders)
        @Assert(!config.enableMdns)

        remove(path)
    }

    @TestCase
    public func loadAppConfigReadsLocalSendTomlPolicyAndArgsOverride(): Unit {
        let scope = testTempToken("soonlink_localsend_toml")
        let path = "/tmp/${scope}.toml"
        let fileMgr = LocalFileMgr()
        fileMgr.writeText(
            path,
            "[soonlink]\n" +
            "localsend_enabled = \"true\"\n" +
            "localsend_discovery_enabled = \"true\"\n" +
            "localsend_announce_enabled = \"true\"\n" +
            "localsend_announce_interval_seconds = \"7\"\n" +
            "localsend_alias = \"SoonLink Lab\"\n" +
            "localsend_fingerprint = \"fp-soonlink\"\n" +
            "localsend_device_model = \"SoonLink\"\n" +
            "localsend_device_type = \"desktop\"\n" +
            "localsend_download_enabled = \"false\"\n" +
            "localsend_accept_policy = \"whitelist\"\n" +
            "localsend_default_save_dir = \"/Inbox\"\n" +
            "localsend_whitelist = \"fp-ok,Cool Carrot\"\n" +
            "localsend_blacklist = \"fp-bad\"\n",
            false
        )

        let config = loadAppConfig(["soonlink", "--config=${path}", "--localsend-accept-policy=auto"])

        @Assert(config.localSendEnabled)
        @Assert(config.localSendDiscoveryEnabled)
        @Assert(config.localSendAnnounceEnabled)
        @Assert(config.localSendAnnounceIntervalSeconds, 7)
        @Assert(config.localSendAlias, "SoonLink Lab")
        @Assert(config.localSendFingerprint, "fp-soonlink")
        @Assert(config.localSendDeviceModel, "SoonLink")
        @Assert(config.localSendDeviceType, "desktop")
        @Assert(!config.localSendDownloadEnabled)
        @Assert(config.localSendAcceptPolicy, "auto")
        @Assert(config.localSendDefaultSaveDir, "/Inbox")
        @Assert(config.localSendWhitelist, "fp-ok,Cool Carrot")
        @Assert(config.localSendBlacklist, "fp-bad")

        remove(path)
    }

    @TestCase
    public func loadTomlReportsBadLineWithLocation(): Unit {
        let scope = testTempToken("soonlink_bad_toml")
        let path = "/tmp/${scope}.toml"
        LocalFileMgr().writeText(path, "[soonlink]\nnot-valid\n", false)

        var rejected = false
        try {
            let _ = TomlConfigStore(path).load()
        } catch (e: Exception) {
            rejected = e.message.contains(path) && e.message.contains(":2")
        }

        @Assert(rejected)
        remove(path)
    }
}
