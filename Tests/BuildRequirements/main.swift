import Foundation
import ProjectDescription

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
func reject(_ message: String, _ operation: () throws -> Void) {
    do { try operation(); preconditionFailure("Expected rejection: \(message)") }
    catch let error as FeatureBuildConfiguration.Failure {
        require(error.message.contains(message), "Wrong rejection: \(error.message)")
    } catch { preconditionFailure("Unexpected error: \(error)") }
}

let base: [String: Plist.Value] = ["CFBundleDisplayName": "Host", "CFBundleVersion": "4"]
let group: [String: Plist.Value] = ["com.apple.security.application-groups": ["group.host"]]
let unchanged = try FeatureBuildConfiguration().compose(infoPlist: base, entitlements: group)
require(unchanged.infoPlist == base && unchanged.entitlements == group, "Empty configuration changed host")

let a = FeatureBuildRequirement(owner: "camera", infoPlist: [
    "NSCameraUsageDescription": "Take photos", "UIBackgroundModes": ["audio"],
    "CustomOptions": ["enabled": true, "quality": 3],
], entitlements: ["com.apple.security.application-groups": ["group.camera"]])
let b = FeatureBuildRequirement(owner: "scanner", infoPlist: [
    "NSCameraUsageDescription": "Scan documents", "UIBackgroundModes": ["processing", "audio"],
], entitlements: ["com.apple.security.application-groups": ["group.host"]])
reject("NSCameraUsageDescription") {
    _ = try FeatureBuildConfiguration(features: [a, b]).compose(infoPlist: base, entitlements: group)
}
let resolved = FeatureBuildConfiguration(features: [a, b],
    infoPlistResolutions: ["NSCameraUsageDescription": "Camera takes photos; Scanner scans documents"])
let composed = try resolved.compose(infoPlist: base, entitlements: group)
require(composed.infoPlist["UIBackgroundModes"] == ["audio", "processing"], "Set merge lost or duplicated modes")
require(composed.infoPlist["CustomOptions"] == ["enabled": true, "quality": 3], "Custom plist values restricted")
require(composed.entitlements["com.apple.security.application-groups"] == ["group.camera", "group.host"], "Group union failed")
let reversed = try FeatureBuildConfiguration(features: [b, a], infoPlistResolutions: resolved.infoPlistResolutions)
    .compose(infoPlist: base, entitlements: group)
require(composed.infoPlist == reversed.infoPlist && composed.entitlements == reversed.entitlements, "Set result depends on Feature order")
let otherTarget = try FeatureBuildConfiguration().compose(infoPlist: [:], entitlements: group)
require(otherTarget.infoPlist["NSCameraUsageDescription"] == nil && otherTarget.entitlements == group, "Requirements leaked to another target")

reject("unique") { _ = try FeatureBuildConfiguration(features: [a, a]).compose(infoPlist: [:], entitlements: [:]) }
reject("nonempty") { _ = try FeatureBuildConfiguration(features: [.init(owner: " ")]).compose(infoPlist: [:], entitlements: [:]) }
reject("CFBundleIdentifier") {
    _ = try FeatureBuildConfiguration(features: [.init(owner: "bad", infoPlist: ["CFBundleIdentifier": "other.app"])])
        .compose(infoPlist: [:], entitlements: [:])
}
reject("string array") {
    _ = try FeatureBuildConfiguration(features: [.init(owner: "bad", infoPlist: ["UIBackgroundModes": [true]])])
        .compose(infoPlist: [:], entitlements: [:])
}
reject("Unused") {
    _ = try FeatureBuildConfiguration(infoPlistResolutions: ["missing": "value"]).compose(infoPlist: [:], entitlements: [:])
}
reject("string array") {
    _ = try FeatureBuildConfiguration(features: [a], infoPlistResolutions: ["UIBackgroundModes": true])
        .compose(infoPlist: [:], entitlements: [:])
}
reject("aps-environment") {
    _ = try FeatureBuildConfiguration(features: [.init(owner: "push", entitlements: ["aps-environment": "production"])])
        .compose(infoPlist: [:], entitlements: ["aps-environment": "development"])
}
let hostURL: Plist.Value = ["CFBundleURLName": "host", "CFBundleURLSchemes": ["host"]]
let aURL: Plist.Value = ["CFBundleURLName": "feature.a", "CFBundleURLSchemes": ["shared", "callback-a"],
                        "CFBundleTypeRole": "Viewer", "CFBundleURLIconFile": "AIcon", "CustomMetadata": ["value": 3]]
let bURL: Plist.Value = ["CFBundleURLName": "feature.b", "CFBundleURLSchemes": ["shared", "callback-b"], "CFBundleTypeRole": "Editor"]
let anonymousURL: Plist.Value = ["CFBundleURLSchemes": ["anonymous"]]
let urlA = FeatureBuildRequirement(owner: "a", infoPlist: ["CFBundleURLTypes": .array([aURL, anonymousURL])])
let urlB = FeatureBuildRequirement(owner: "b", infoPlist: ["CFBundleURLTypes": .array([bURL, aURL, anonymousURL])])
let urls = try FeatureBuildConfiguration(features: [urlA, urlB]).compose(
    infoPlist: ["CFBundleURLTypes": .array([hostURL])], entitlements: [:])
require(urls.infoPlist["CFBundleURLTypes"] == .array([hostURL, aURL, anonymousURL, bURL]), "URL declarations lost fields, host, or exact deduplication")
let afterRemoval = try FeatureBuildConfiguration(features: [urlA]).compose(
    infoPlist: ["CFBundleURLTypes": .array([hostURL])], entitlements: [:])
require(afterRemoval.infoPlist["CFBundleURLTypes"] == .array([hostURL, aURL, anonymousURL]), "Removing B changed A/host declarations")
let conflictingURL: Plist.Value = ["CFBundleURLName": "feature.a", "CFBundleURLSchemes": ["other"], "CFBundleTypeRole": "Editor"]
let conflicting = FeatureBuildRequirement(owner: "conflict", infoPlist: ["CFBundleURLTypes": .array([conflictingURL])])
reject("name feature.a requested by a, conflict") {
    _ = try FeatureBuildConfiguration(features: [urlA, conflicting]).compose(infoPlist: [:], entitlements: [:])
}
let explicitURLs: Plist.Value = .array([hostURL, conflictingURL])
let resolvedURLs = try FeatureBuildConfiguration(features: [urlA, conflicting], infoPlistResolutions: ["CFBundleURLTypes": explicitURLs])
    .compose(infoPlist: [:], entitlements: [:])
require(resolvedURLs.infoPlist["CFBundleURLTypes"] == explicitURLs, "Explicit URL conflict decision ignored")
let malformedURLTypes: [Plist.Value] = [true, ["not-a-dictionary"]]
for bad in malformedURLTypes {
    reject("dictionary array") {
        _ = try FeatureBuildConfiguration(features: [.init(owner: "bad", infoPlist: ["CFBundleURLTypes": bad])])
            .compose(infoPlist: [:], entitlements: [:])
    }
}
reject("string array for CFBundleURLSchemes") {
    _ = try FeatureBuildConfiguration(features: [.init(owner: "bad", infoPlist: ["CFBundleURLTypes": [["CFBundleURLSchemes": [true]]]])])
        .compose(infoPlist: [:], entitlements: [:])
}
require(otherTarget.infoPlist["CFBundleURLTypes"] == nil, "URL declarations leaked to another target")
let identical = try FeatureBuildConfiguration(features: [.init(owner: "same", infoPlist: ["CFBundleVersion": "4"])])
    .compose(infoPlist: base, entitlements: group)
require(identical.infoPlist == base, "Identical setting rejected")
let activities = try FeatureBuildConfiguration(features: [.init(owner: "activity", infoPlist: ["NSUserActivityTypes": ["custom", "native"]])])
    .compose(infoPlist: ["NSUserActivityTypes": ["native"]], entitlements: [:])
require(activities.infoPlist["NSUserActivityTypes"] == ["custom", "native"], "Activity types lost host continuation")
let entitlementResolution = try FeatureBuildConfiguration(features: [.init(owner: "push", entitlements: ["aps-environment": "production"])],
    entitlementResolutions: ["aps-environment": "development"]).compose(infoPlist: [:], entitlements: ["aps-environment": "development"])
require(entitlementResolution.entitlements["aps-environment"] == "development", "Explicit entitlement resolution ignored")
let localizedA = FeatureBuildRequirement(owner: "localized-a", localizedInfoPlist: [
    "en": ["NSCameraUsageDescription": "Use camera", "CFBundleDisplayName": "Shared"],
    "ja": ["NSCameraUsageDescription": "カメラを使用", "CFBundleDisplayName": "共有"],
])
let localizedB = FeatureBuildRequirement(owner: "localized-b", localizedInfoPlist: [
    "en": ["NSCameraUsageDescription": "Scan documents", "CFBundleDisplayName": "Shared"],
    "ja": ["NSCameraUsageDescription": "書類を撮影", "CFBundleDisplayName": "共有"],
])
reject("locale en key NSCameraUsageDescription") {
    _ = try FeatureBuildConfiguration(features: [localizedA, localizedB]).compose(infoPlist: [:], entitlements: [:])
}
let localized = try FeatureBuildConfiguration(features: [localizedA, localizedB],
    localizedInfoPlistResolutions: [
        "en": ["NSCameraUsageDescription": "Use camera to scan documents"],
        "ja": ["NSCameraUsageDescription": "カメラで書類を撮影します"],
    ]).compose(infoPlist: [:], entitlements: [:])
require(localized.localizedInfoPlist["en"]?["CFBundleDisplayName"] == "Shared", "Identical localized value lost")
require(localized.localizedInfoPlist["ja"]?["NSCameraUsageDescription"] == "カメラで書類を撮影します", "Localized resolution ignored")
reject("requested by host, localized-a") {
    _ = try FeatureBuildConfiguration(features: [localizedA]).compose(
        infoPlist: [:], entitlements: [:],
        localizedInfoPlist: ["en": ["NSCameraUsageDescription": "Host camera text"]])
}
let hostResolved = try FeatureBuildConfiguration(features: [localizedA],
    localizedInfoPlistResolutions: ["en": ["NSCameraUsageDescription": "Host and Feature camera text"]])
    .compose(infoPlist: [:], entitlements: [:],
             localizedInfoPlist: ["en": ["NSCameraUsageDescription": "Host camera text"]])
require(hostResolved.localizedInfoPlist["en"]?["NSCameraUsageDescription"] == "Host and Feature camera text", "Host localized resolution ignored")
let widgetLocalized = try FeatureBuildConfiguration(features: [
    .init(owner: "widget", localizedInfoPlist: ["en": ["CFBundleDisplayName": "Probe Widget"]])
]).compose(infoPlist: [:], entitlements: [:])
require(widgetLocalized.localizedInfoPlist["en"]?["CFBundleDisplayName"] == "Probe Widget", "Widget localization lost")
require(widgetLocalized.localizedInfoPlist["ja"] == nil && localized.localizedInfoPlist["en"]?["CFBundleDisplayName"] != "Probe Widget", "Target localizations leaked")
reject("invalid characters") {
    _ = try FeatureBuildConfiguration(features: [.init(owner: "bad-locale", localizedInfoPlist: ["../ja": ["Key": "Value"]])])
        .compose(infoPlist: [:], entitlements: [:])
}
reject("key must be nonempty") {
    _ = try FeatureBuildConfiguration(features: [.init(owner: "bad-key", localizedInfoPlist: ["en": [" ": "Value"]])])
        .compose(infoPlist: [:], entitlements: [:])
}
reject("Unused InfoPlist.strings resolution") {
    _ = try FeatureBuildConfiguration(features: [localizedA], localizedInfoPlistResolutions: ["en": ["Unused": "Value"]])
        .compose(infoPlist: [:], entitlements: [:])
}
let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: output) }
let staleLocale = output.appendingPathComponent("fr.lproj")
try FileManager.default.createDirectory(at: staleLocale, withIntermediateDirectories: true)
let staleInfo = staleLocale.appendingPathComponent("InfoPlist.strings")
let unrelated = staleLocale.appendingPathComponent("Localizable.strings")
try Data("stale".utf8).write(to: staleInfo)
try Data("keep".utf8).write(to: unrelated)
try localized.writeLocalizedInfoPlistStrings(to: output.path)
require(!FileManager.default.fileExists(atPath: staleInfo.path), "Stale InfoPlist.strings survived regeneration")
require(FileManager.default.fileExists(atPath: unrelated.path), "Unrelated localized resource was deleted")
print("Feature build requirement checks passed: baseline, union, conflict, resolution, custom values, target isolation, validation")
