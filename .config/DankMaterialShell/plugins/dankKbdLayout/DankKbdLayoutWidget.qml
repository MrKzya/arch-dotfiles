import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ── State ─────────────────────────────────────────────────
    property var    layoutNames: []
    property int    activeIndex: 0
    property bool   loaded:      false

    // ── Settings from plugin config ───────────────────────────
    readonly property bool  showIcon:   pluginData.showIcon  !== undefined ? pluginData.showIcon  : true
    readonly property bool  showBadge:  pluginData.showBadge !== undefined ? pluginData.showBadge : true
    readonly property int   pillWidth:  (pluginData.pillWidth ?? 0)

    readonly property string activeShort: {
        if (!loaded || layoutNames.length === 0) return "??"
        const full = layoutNames[activeIndex] ?? ""
        if (!full) return "??"
        // "English (US)" → "US"   |   "Russian" → "RU"
        const m = full.match(/\(([^)]+)\)/)
        if (m) return m[1].slice(0, 2).toUpperCase()
        return full.slice(0, 2).toUpperCase()
    }

    // ── Fetch once on load ─────────────────────────────────────
    Process {
        id: fetchProc
        running: true
        command: ["niri", "msg", "-j", "keyboard-layouts"]

        stdout: SplitParser {
            onRead: function(line) {
                if (!line.trim()) return
                try {
                    const obj = JSON.parse(line)
                    // flat: {"names":[...],"current_idx":N}
                    // or wrapped: {"Ok":{"KeyboardLayouts":{...}}}
                    const kl = (Array.isArray(obj?.names) ? obj : null)
                              ?? obj?.Ok?.KeyboardLayouts
                              ?? obj?.keyboard_layouts
                    if (kl) {
                        root.layoutNames = kl.names       ?? []
                        root.activeIndex = kl.current_idx ?? 0
                        root.loaded      = true
                    }
                } catch(e) {
                    console.warn("KeyboardLayout fetch:", e, line)
                }
            }
        }
        stderr: SplitParser {
            onRead: line => console.warn("KeyboardLayout stderr:", line)
        }
    }

    // ── Live event stream ──────────────────────────────────────
    Process {
        id: eventStream
        running: true
        command: ["niri", "msg", "-j", "event-stream"]

        stdout: SplitParser {
            onRead: function(line) {
                if (!line.trim()) return
                try {
                    const msg = JSON.parse(line)
                    // fired on layout list change: names + current_idx
                    const changed = msg?.KeyboardLayoutsChanged?.keyboard_layouts
                    if (changed) {
                        if (Array.isArray(changed.names) && changed.names.length)
                            root.layoutNames = changed.names
                        if (changed.current_idx !== undefined)
                            root.activeIndex = changed.current_idx
                        root.loaded = true
                    }
                    // fired on every actual switch: just the new index
                    const switched = msg?.KeyboardLayoutSwitched
                    if (switched?.idx !== undefined) {
                        root.activeIndex = switched.idx
                        root.loaded = true
                    }
                } catch(e) {}
            }
        }
    }

    // ── Cycle to next layout ───────────────────────────────────
    function cycleLayout() {
        if (layoutNames.length < 2) return
        Quickshell.execDetached(["niri", "msg", "action", "switch-layout", "next"])
    }

    // ── Horizontal bar pill ────────────────────────────────────
    horizontalBarPill: Component {
        Item {
            implicitWidth:  root.pillWidth > 0 ? root.pillWidth : pillRow.implicitWidth + 12
            implicitHeight: pillRow.implicitHeight + 4

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                // DankIcon {
                //     name: "keyboard"
                //     size: Theme.iconSize
                //     color: root.loaded ? Theme.surfaceVariantText : Theme.surfaceVariantText
                //     anchors.verticalCenter: parent.verticalCenter
                //     visible: root.showIcon
                //     width:   root.showIcon ? Theme.iconSize : 0
                // }

                StyledText {
                    text: root.activeShort
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight:    Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Rectangle {
                //     visible: root.showBadge && root.layoutNames.length > 1
                //     width:   badgeText.implicitWidth + 6
                //     height:  16
                //     radius:  4
                //     color:   Theme.withAlpha(Theme.primary, 0.18)
                //     anchors.verticalCenter: parent.verticalCenter

                //     StyledText {
                //         id:    badgeText
                //         anchors.centerIn: parent
                //         text:  (root.activeIndex + 1) + "/" + root.layoutNames.length
                //         font.pixelSize: Theme.fontSizeXSmall
                //         color: Theme.primary
                //     }
                // }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape:  Qt.PointingHandCursor
                onClicked:    root.cycleLayout()
            }
        }
    }

    // ── Vertical bar pill ──────────────────────────────────────
    verticalBarPill: Component {
        Item {
            implicitWidth:  Theme.iconSize + 8
            implicitHeight: Theme.iconSize + Theme.fontSizeMedium + Theme.spacingXS + 8

            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: "keyboard"
                    size: Theme.iconSize
                    color: root.loaded ? Theme.surfaceVariantText : Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.showIcon
                    height:  root.showIcon ? Theme.iconSize : 0
                }

                StyledText {
                    text: root.activeShort
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight:    Font.Medium
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape:  Qt.PointingHandCursor
                onClicked:    root.cycleLayout()
            }
        }
    }
}
