package soonlnk.tests

import soonlnk.commons.*
import soonlnk.features.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class EndpointModel_test {
    @TestCase
    public func normalizeEndpointMetadataAndResolveOrigin(): Unit {
        let device = Device(id: "edge-node")
        device.deviceType = "remote"
        device.connectorType = "soonlink-http"
        device.endpointScheme = "tls"
        device.endpointBasePath = "gateway//soonlink/"
        device.ip = "node.example.com"
        device.port = 19443

        applyDefaultDeviceEndpoint(device)

        @Assert(device.endpointScheme, "https")
        @Assert(device.endpointBasePath, "/gateway/soonlink")
        @Assert(resolveDeviceEndpointOrigin(device), "https://node.example.com:19443/gateway/soonlink")
    }

    @TestCase
    public func buildSoonLinkNodeBaseUrlSupportsReverseProxyPaths(): Unit {
        @Assert(
            buildSoonLinkNodeBaseUrl("10.0.0.8", 19090, "tls", "relay/node/"),
            "https://10.0.0.8:19090/relay/node"
        )
        @Assert(
            buildSoonLinkNodeBaseUrl("edge.example.internal", 0, "", "/soonlink"),
            "http://edge.example.internal/soonlink"
        )
    }
}
