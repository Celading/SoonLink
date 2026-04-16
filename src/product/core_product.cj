package soonlnk.product

import soonlnk.commons.*
import soonlnk.master.*
public interface ProductApp {
    func name(): String
    func start(): Unit
    func stop(): Unit
}

public class SoonLinkProduct <: ProductApp {
    public let runtime: RuntimeProfile
    public let config: AppConfig
    public let coreServer: CoreServer
    public let webServer: WebServer

    public init(config: AppConfig, runtime!: RuntimeProfile = currentRuntimeProfile()) {
        let normalized = normalizeAppConfigForRuntime(config, runtime)
        this.runtime = runtime
        this.config = normalized
        this.coreServer = CoreServer(normalized, profile: runtime)
        this.webServer = WebServer(coreServer, normalized.webPort)
    }

    public func name(): String { runtime.productName }

    public func start(): Unit {
        coreServer.start()
        webServer.start()
    }

    public func stop(): Unit {
        webServer.stop()
        coreServer.stop()
    }
}

public func buildCoreProduct(config: AppConfig): SoonLinkProduct {
    SoonLinkProduct(config, runtime: defaultRuntimeProfile())
}

public func buildProduct(config: AppConfig): ProductApp {
    SoonLinkProduct(config, runtime: currentRuntimeProfile())
}
