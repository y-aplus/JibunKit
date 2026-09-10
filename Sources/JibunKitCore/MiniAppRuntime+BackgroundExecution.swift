import Foundation

#if canImport(UIKit) && !os(watchOS)
public extension MiniAppRuntime {
    /// Ends every still-active assertion during this runtime's awaited shutdown.
    func makeBackgroundExecution(
        context: MiniAppContext
    ) throws -> MiniAppBackgroundExecution {
        let execution = MiniAppBackgroundExecution(context: context)
        try onShutdown { execution.endAll() }
        return execution
    }
}
#endif

extension MiniAppRuntime {
    func makeBackgroundExecution(
        context: MiniAppContext,
        provider: any MiniAppBackgroundAssertionProviding
    ) throws -> MiniAppBackgroundExecution {
        let execution = MiniAppBackgroundExecution(context: context, provider: provider)
        try onShutdown { execution.endAll() }
        return execution
    }
}
