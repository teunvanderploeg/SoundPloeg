import Foundation

/// External launch and preview routing. Opening the app is never a speech request.
struct AppLaunchOptions: Equatable {
    enum Destination: Equatable {
        case settings
        case previewSettings
        case previewMenu
    }

    let isDesignPreview: Bool
    let previewMenu: Bool
    let showSettingsOnLaunch: Bool

    init(arguments: [String], info: [String: Any] = [:]) {
        let bundlePreview = info["PloegDesignPreview"] as? Bool == true
        let menuArgument = arguments.contains("--design-preview-menu")
        let menuMetadata = bundlePreview &&
            (info["PloegDesignPreviewMode"] as? String)?.lowercased() == "menu"
        previewMenu = menuArgument || menuMetadata
        isDesignPreview = previewMenu || bundlePreview || arguments.contains("--design-preview")
        showSettingsOnLaunch = arguments.contains("--show-settings")
    }

    var initialDestination: Destination? {
        if isDesignPreview { return previewMenu ? .previewMenu : .previewSettings }
        return showSettingsOnLaunch ? .settings : nil
    }

    var reopenDestination: Destination {
        isDesignPreview ? (previewMenu ? .previewMenu : .previewSettings) : .settings
    }
}
