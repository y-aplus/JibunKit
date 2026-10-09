import Foundation
import ProjectDescription

/// A Feature package under `Modules/` that declares its host connection in
/// `JibunKitFeature.json`. `Tools/jibunkit-feature.py sync` writes the list in
/// `ModuleFeatures.swift`; Tuist reads that generated helper, so adding a
/// Feature changes the manifest inputs and is not hidden by manifest caching.
public struct ModuleFeature: Sendable {
    public let id: String
    public let path: String
    public let products: [String]
    public let sources: [String]
    public let definitions: [String]
    public let widgetProducts: [String]
    public let widgetSources: [String]
    public let widgets: [String]
    public let app: FeatureBuildRequirement?
    public let widget: FeatureBuildRequirement?
    public let appShortcuts: FeatureAppShortcuts?

    public init(id: String, path: String, products: [String] = [], sources: [String] = [],
                definitions: [String] = [], widgetProducts: [String] = [], widgetSources: [String] = [],
                widgets: [String] = [], app: FeatureBuildRequirement? = nil,
                widget: FeatureBuildRequirement? = nil, appShortcuts: FeatureAppShortcuts? = nil) {
        self.id = id
        self.path = path
        self.products = products
        self.sources = sources
        self.definitions = definitions
        self.widgetProducts = widgetProducts
        self.widgetSources = widgetSources
        self.widgets = widgets
        self.app = app
        self.widget = widget
        self.appShortcuts = appShortcuts
    }
}

extension ModuleFeatures {
    public static var packages: [Package] {
        all.map { .package(path: .relativeToManifest($0.path)) }
    }

    public static var appDependencies: [TargetDependency] {
        all.flatMap { $0.products.map { .package(product: $0) } }
    }

    public static var appSources: [SourceFileGlob] {
        all.flatMap { feature in feature.sources.map { .glob(.relativeToManifest("\(feature.path)/\($0)")) } }
    }

    public static var widgetDependencies: [TargetDependency] {
        all.flatMap { $0.widgetProducts.map { .package(product: $0) } }
    }

    public static var widgetSources: [SourceFileGlob] {
        all.flatMap { feature in feature.widgetSources.map { .glob(.relativeToManifest("\(feature.path)/\($0)")) } }
    }

    public static var appRequirements: [FeatureBuildRequirement] { all.compactMap(\.app) }
    public static var widgetRequirements: [FeatureBuildRequirement] { all.compactMap(\.widget) }
    public static var appShortcuts: [FeatureAppShortcuts] { all.compactMap(\.appShortcuts) }

    /// Writes the app's registry additions and the widget bundle additions.
    /// Both files are replaced on every generation, also when no module exists.
    public static func writeSources(registry: String, widgets: String) throws {
        let appImports = Set(all.flatMap(\.products)).sorted()
        let registrySource = """
            // Generated from Modules/*/JibunKitFeature.json; edit those files instead.
            #if os(iOS)
            import JibunKitCore
            \(appImports.map { "import \($0)\n" }.joined())
            @MainActor
            enum ModuleFeatureRegistry {
                static var definitions: [MiniAppDefinition] {
                    [
            \(all.flatMap(\.definitions).map { "            \($0),\n" }.joined())        ]
                }
            }
            #endif

            """
        let widgetImports = Set(all.flatMap(\.widgetProducts)).sorted()
        let widgetSource = """
            // Generated from Modules/*/JibunKitFeature.json; edit those files instead.
            #if os(iOS)
            import SwiftUI
            import WidgetKit
            \(widgetImports.map { "import \($0)\n" }.joined())
            enum ModuleWidgets {
                @MainActor @WidgetBundleBuilder
                static var all: some Widget {
            \(all.flatMap(\.widgets).map { "        \($0)\n" }.joined())    }
            }
            #endif

            """
        for (source, destination) in [(registrySource, registry), (widgetSource, widgets)] {
            let target = URL(fileURLWithPath: destination)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: target, atomically: true, encoding: .utf8)
        }
    }
}
