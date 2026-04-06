package soonlnk.tests

import soonlnk.commons.*
import soonlnk.features.*
import soonlnk.master.*
import soonlnk.product.*
import std.collection.ArrayList
import std.fs.remove
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class DeviceRegistryStore_test {
    @TestCase
    public func saveAndLoadRegistry(): Unit {
        let path = testTempPath("soonlink_devices") + ".json"
        let store = JsonDeviceRegistryStore(path)

        let records = ArrayList<DeviceRegistryRecord>()
        let r1 = DeviceRegistryRecord()
        r1.id = "dev-1"
        r1.name = "Node-1"
        r1.deviceType = "remote"
        r1.ip = "192.168.1.5"
        r1.port = 8081
        r1.endpointScheme = "https"
        r1.endpointBasePath = "/gateway"
        r1.online = true
        r1.lastSeen = currentTimestamp()
        r1.trustState = Trusted
        r1.trustSource = "pin"
        r1.trustUpdatedAt = currentTimestamp()
        records.add(r1)

        let r2 = DeviceRegistryRecord()
        r2.id = "dev-2"
        r2.name = "Node-2"
        r2.deviceType = "remote"
        r2.ip = "192.168.1.6"
        r2.port = 8082
        r2.online = false
        r2.lastSeen = currentTimestamp()
        r2.trustState = Blocked
        r2.trustSource = "admin"
        r2.trustUpdatedAt = currentTimestamp()
        records.add(r2)

        store.save(records)

        let loaded = store.load()
        @Assert(loaded.size, 2)
        @Assert(loaded[0].id, "dev-1")
        @Assert(loaded[1].id, "dev-2")
        @Assert(loaded[0].endpointScheme, "https")
        @Assert(loaded[0].endpointBasePath, "/gateway")
        @Assert(deviceTrustStateToString(loaded[0].trustState), "trusted")
        @Assert(loaded[0].trustSource, "pin")
        @Assert(deviceTrustStateToString(loaded[1].trustState), "blocked")
        @Assert(loaded[1].trustSource, "admin")

        remove(path)
    }
}
