package soonlnk.product

import soonlnk.commons.*
import soonlnk.master.*
public interface ProductApp {
    func name(): String
    func start(): Unit
    func stop(): Unit
}

public class SoonLinkProduct <: ProductApp {
    public let profile: ProductProfile
    public let config: AppConfig
    public let coreServer: CoreServer
    public let webServer: WebServer

    public init(config: AppConfig, profile!: ProductProfile = resolveProductProfile()) {
        let normalized = normalizeAppConfigForProfile(config, profile)
        this.profile = profile
        this.config = normalized
        this.coreServer = CoreServer(normalized, profile: profile)
        this.webServer = WebServer(coreServer, normalized.webPort)
    }

    public func name(): String { profile.productName }

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
    SoonLinkProduct(config, profile: coreProductProfile())
}

public func buildProProduct(config: AppConfig): SoonLinkProduct {
    SoonLinkProduct(config, profile: proProductProfile())
}

public func buildFullProduct(config: AppConfig): SoonLinkProduct {
    SoonLinkProduct(config, profile: fullProductProfile())
}

public func buildProduct(config: AppConfig): ProductApp {
    SoonLinkProduct(config, profile: resolveProductProfile())
}
