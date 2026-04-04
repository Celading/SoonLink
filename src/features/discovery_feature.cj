package soonlnk.features

import soonlnk.commons.*
import std.collection.{ArrayList, HashMap}
import std.sync.Mutex

public class DiscoveryFeature {
    let registryStore: DeviceRegistryStore
    let udpTransport: DiscoveryTransport
    let mdnsTransport: DiscoveryTransport

    let mutex: Mutex = Mutex()
    var registry: HashMap<String, DeviceRegistryRecord> = HashMap<String, DeviceRegistryRecord>()
    var running: Bool = false
    var onDeviceFound: ?(DeviceRegistryRecord) -> Unit = None

    public init(
        registryStore: DeviceRegistryStore,
        udpTransport: DiscoveryTransport,
        mdnsTransport: DiscoveryTransport
    ) {
        this.registryStore = registryStore
        this.udpTransport = udpTransport
        this.mdnsTransport = mdnsTransport
    }

    public func setDeviceFoundCallback(callback: (DeviceRegistryRecord) -> Unit): Unit {
        onDeviceFound = callback
    }

    public func start(): Unit {
        if (running) { return }
        running = true

        loadPersistedRegistry()

        udpTransport.start({ packet: DiscoveryPacket =>
            acceptPacket(packet)
        })

        mdnsTransport.start({ packet: DiscoveryPacket =>
            acceptPacket(packet)
        })
    }

    public func stop(): Unit {
        if (!running) { return }
        running = false
        udpTransport.stop()
        mdnsTransport.stop()
        persistRegistry()
    }

    public func manualRegister(record: DeviceRegistryRecord): Unit {
        if (record.id.size == 0) { return }
        record.lastSeen = currentTimestamp()
        synchronized(mutex) {
            registry.add(record.id, record)
        }
        persistRegistry()
        if (let Some(cb) <- onDeviceFound) {
            cb(record)
        }
    }

    public func getRecord(deviceId: String): ?DeviceRegistryRecord {
        synchronized(mutex) {
            registry.get(deviceId)
        }
    }

    public func removeRecord(deviceId: String): Bool {
        if (deviceId.size == 0) {
            return false
        }

        var removed = false
        synchronized(mutex) {
            match (registry.get(deviceId)) {
                case Some(_) =>
                    registry.remove(deviceId)
                    removed = true
                case None => ()
            }
        }

        if (removed) {
            persistRegistry()
        }
        removed
    }

    public func publishHeartbeat(record: DeviceRegistryRecord): Unit {
        if (!running) { return }

        let packet = DiscoveryPacket()
        packet.deviceId = record.id
        packet.name = record.name
        packet.deviceType = record.deviceType
        packet.ip = record.ip
        packet.port = record.port
        packet.timestamp = currentTimestamp()

        udpTransport.publishHeartbeat(packet)
        mdnsTransport.publishHeartbeat(packet)
    }

    public func listRegistry(): ArrayList<DeviceRegistryRecord> {
        let out = ArrayList<DeviceRegistryRecord>()
        synchronized(mutex) {
            for ((_, record) in registry) {
                out.add(record)
            }
        }
        out
    }

    public func persistRegistry(): Unit {
        let records = listRegistry()
        registryStore.save(records)
    }

    public func loadPersistedRegistry(): Unit {
        let records = registryStore.load()
        synchronized(mutex) {
            for (record in records) {
                registry.add(record.id, record)
            }
        }
    }

    func acceptPacket(packet: DiscoveryPacket): Unit {
        if (packet.deviceId.size == 0) {
            return
        }

        let record = DeviceRegistryRecord()
        record.id = packet.deviceId
        record.name = packet.name
        record.deviceType = packet.deviceType
        record.ip = packet.ip
        record.port = packet.port
        record.online = true
        record.lastSeen = packet.timestamp

        synchronized(mutex) {
            registry.add(record.id, record)
        }

        if (let Some(cb) <- onDeviceFound) {
            cb(record)
        }
    }
}
