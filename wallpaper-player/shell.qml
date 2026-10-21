import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Проигрыватель видео-обоев Glide Shell — отдельный процесс (qs -p эта папка), его запускает Wallpaper.qml.
// Видео декодируется здесь, а не в оболочке: без аппаратного декодера это десятки процентов ядра, и в одном
// процессе с баром и панелью интерфейс переставал отвечать. Что играть и где стоять на паузе — пишет оболочка в
// $XDG_RUNTIME_DIR/glide-shell-wallpaper.json: {video, still, fit, live: {выход: bool}}.
ShellRoot {
    id: root
    property var st: ({})
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/glide-shell-wallpaper.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.st = JSON.parse(text()) } catch (e) {} }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "glide-wallpaper-video"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "black"
            mask: Region {}
            readonly property bool live: !!root.st.live && root.st.live[modelData.name] !== false
            readonly property bool fit: root.st.fit === "fit"

            Image {   // кадр-заставка, пока видео грузится
                anchors.fill: parent
                source: root.st.still || ""
                fillMode: win.fit ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                sourceSize.width: win.width; sourceSize.height: win.height
                asynchronous: true
            }
            MediaPlayer {
                id: player
                source: root.st.video || ""
                loops: MediaPlayer.Infinite
                videoOutput: vo
                onSourceChanged: if (source.toString() !== "" && win.live) play()
            }
            Connections {
                target: win
                function onLiveChanged() {
                    if (player.source.toString() === "") return
                    if (win.live) player.play(); else player.pause()
                }
            }
            VideoOutput {
                id: vo
                anchors.fill: parent
                fillMode: win.fit ? VideoOutput.PreserveAspectFit : VideoOutput.PreserveAspectCrop
                opacity: player.position > 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
        }
    }
}
