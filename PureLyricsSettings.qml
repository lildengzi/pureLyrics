import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "pureLyrics"

    // ── Display ──────────────────────────────────────────────────────────────
    SliderSetting {
        settingKey: "fontSize"
        label: I18n.tr("Font Size")
        description: I18n.tr("Size of the lyric text")
        defaultValue: 22
        minimum: 12
        maximum: 64
        unit: "px"
    }

    SelectionSetting {
        settingKey: "lineCount"
        label: I18n.tr("Lines Shown")
        description: I18n.tr("Total lyric lines displayed")
        defaultValue: "3"
        options: [
            { label: "1", value: "1" },
            { label: "3", value: "3" },
            { label: "5", value: "5" },
            { label: "7", value: "7" }
        ]
    }

    SelectionSetting {
        settingKey: "textAlign"
        label: I18n.tr("Alignment")
        defaultValue: "center"
        options: [
            { label: I18n.tr("Left"), value: "left" },
            { label: I18n.tr("Center"), value: "center" },
            { label: I18n.tr("Right"), value: "right" }
        ]
    }

    SliderSetting {
        settingKey: "scrollOffset"
        label: I18n.tr("Sync Offset")
        description: I18n.tr("Adjust lyric timing. Positive shows lines earlier, negative later. (ms)")
        defaultValue: 0
        minimum: -3000
        maximum: 3000
        unit: "ms"
    }

    // ── Accent Color ──────────────────────────────────────────────────────────
    SelectionSetting {
        id: colorModeSetting
        settingKey: "colorMode"
        label: I18n.tr("Accent Color Theme")
        description: I18n.tr("Color of the current lyric line")
        defaultValue: "primary"
        options: [
            { label: I18n.tr("System Primary"), value: "primary" },
            { label: I18n.tr("System Secondary"), value: "secondary" },
            { label: I18n.tr("Custom Color"), value: "custom" }
        ]
    }

    ColorSetting {
        visible: colorModeSetting.value === "custom"
        settingKey: "customColor"
        label: I18n.tr("Custom Accent Color")
        description: I18n.tr("Used when Accent Color Theme is Custom")
        defaultValue: "#6750A4"
    }

    // ── Background ────────────────────────────────────────────────────────────
    SliderSetting {
        settingKey: "backgroundOpacity"
        label: I18n.tr("Background Opacity")
        description: I18n.tr("Rounded background card behind the lyrics (0 = none)")
        defaultValue: 0
        minimum: 0
        maximum: 100
        unit: "%"
    }

    SliderSetting {
        settingKey: "borderOpacity"
        label: I18n.tr("Border Opacity")
        description: I18n.tr("Background card border stroke opacity (0 = no border)")
        defaultValue: 100
        minimum: 0
        maximum: 100
        unit: "%"
    }

    // ── Cache ────────────────────────────────────────────────────────────────
    ToggleSetting {
        settingKey: "cachingEnabled"
        label: I18n.tr("Local Cache")
        description: I18n.tr("Save downloaded lyrics locally to speed up loading times and reduce network requests. (Recommended)")
        defaultValue: true
    }

    // ── Source Priority ──────────────────────────────────────────────────────
    SelectionSetting {
        settingKey: "source1"
        label: I18n.tr("Source 1")
        defaultValue: "lrclib"
        options: [
            { label: "none", value: "none" },
            { label: "navidrome", value: "navidrome" },
            { label: "lrclib", value: "lrclib" },
            { label: "musixmatch", value: "musixmatch" },
            { label: "lrcapi", value: "lrcapi" }
        ]
    }

    SelectionSetting {
        settingKey: "source2"
        label: I18n.tr("Source 2")
        defaultValue: "lrcapi"
        options: [
            { label: "none", value: "none" },
            { label: "navidrome", value: "navidrome" },
            { label: "lrclib", value: "lrclib" },
            { label: "musixmatch", value: "musixmatch" },
            { label: "lrcapi", value: "lrcapi" }
        ]
    }

    SelectionSetting {
        settingKey: "source3"
        label: I18n.tr("Source 3")
        defaultValue: "musixmatch"
        options: [
            { label: "none", value: "none" },
            { label: "navidrome", value: "navidrome" },
            { label: "lrclib", value: "lrclib" },
            { label: "musixmatch", value: "musixmatch" },
            { label: "lrcapi", value: "lrcapi" }
        ]
    }

    SelectionSetting {
        settingKey: "source4"
        label: I18n.tr("Source 4")
        defaultValue: "navidrome"
        options: [
            { label: "none", value: "none" },
            { label: "navidrome", value: "navidrome" },
            { label: "lrclib", value: "lrclib" },
            { label: "musixmatch", value: "musixmatch" },
            { label: "lrcapi", value: "lrcapi" }
        ]
    }

    // ── Navidrome ────────────────────────────────────────────────────────────
    StringSetting {
        settingKey: "navidromeUrl"
        label: I18n.tr("Navidrome Server URL")
        description: I18n.tr("The full address of your Navidrome instance.")
        placeholder: "https://music.example.com:4533"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "navidromeUser"
        label: I18n.tr("Navidrome Username")
        placeholder: "username"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "navidromePassword"
        label: I18n.tr("Navidrome Password")
        placeholder: "password"
        defaultValue: ""
    }

    // ── Player Selection ──────────────────────────────────────────────────────
    SelectionSetting {
        settingKey: "preferredPlayer"
        label: I18n.tr("Preferred Media Player")
        description: I18n.tr("Which MPRIS player to prioritize when multiple are active")
        defaultValue: "auto"
        options: [
            { label: I18n.tr("Auto (Playing Player)"), value: "auto" },
            { label: "Spotify", value: "spotify" },
            { label: "Firefox / Browser", value: "firefox" },
            { label: "Chromium / Chrome", value: "chromium" },
            { label: "mpv", value: "mpv" },
            { label: "VLC", value: "vlc" },
            { label: "termusic", value: "termusic" }
        ]
    }

    ToggleSetting {
        settingKey: "filterDuplicates"
        label: I18n.tr("Filter Duplicate Players")
        description: I18n.tr("Hide duplicate MPRIS player instances")
        defaultValue: true
    }
}
