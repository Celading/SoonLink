package soonlnk.features

import soonlnk.commons.*
public class LogPersistFeature {
    let sink: LogSink
    var enabled: Bool = true

    public init(sink: LogSink) {
        this.sink = sink
    }

    public func bind(logger: LogManager): Unit {
        logger.setOnLogAdded({ entry: LogEntry =>
            if (!enabled) { return }
            sink.append(entry)
        })
    }

    public func setEnabled(enabled: Bool): Unit {
        this.enabled = enabled
    }

    public func isEnabled(): Bool {
        enabled
    }

    public func flush(): Unit {
        sink.flush()
    }
}
