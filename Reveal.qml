import QtQuick
import QtQuick.Effects

// Фигурный уход «покрова» — фона экрана блокировки (заслонка над рабочим столом, предпросмотр) или экрана входа.
// cover — элемент-фон: пока progress > 0, он рисуется только через этот эффект (hideSource), при 0 — как обычно.
// progress 0 → 1: от покрова целиком до пустоты (что под ним — рабочий стол или чёрный экран). Сглаживание
// времени — у того, кто анимирует progress. Без зависимостей от настроек: тот же файл ставит экран входа.
//   rise — растворение; iris — круг раскрывается от originX/originY; curtains — половины разъезжаются;
//   tiles — плитки улетают волной от центра; zoom — пролёт сквозь (приближение с размытием);
//   island — сжимается в пилюлю острова (islandRect) и гаснет.
Item {
    id: rv
    property Item cover
    property real progress: 0
    property string style: "rise"
    property real originX: width / 2
    property real originY: height * 0.53
    property rect islandRect: Qt.rect(width / 2 - 110, 6, 220, 32)

    readonly property bool active: progress > 0.0001 && !!cover
    readonly property real p: Math.max(0, Math.min(1, progress))
    function lerp(a, b, t) { return a + (b - a) * t }

    // весь покров одним снимком — для круга, острова, пролёта и растворения. Снимок и маски готовы заранее,
    // а не в момент старта: включённые на ходу, они не доходили до MultiEffect — оставался второй фон
    // он же прячет сам фон на время эффекта (и для шторок с плитками) — hideSource
    ShaderEffectSource {
        id: full
        anchors.fill: parent
        sourceItem: rv.cover
        hideSource: rv.active
        live: true
        visible: false
    }

    // ---- растворение ----
    MultiEffect {
        anchors.fill: parent
        visible: rv.active && rv.style === "rise"
        source: full
        opacity: 1 - rv.p
    }

    // ---- пролёт сквозь: покров летит навстречу, размываясь ----
    MultiEffect {
        anchors.fill: parent
        visible: rv.active && rv.style === "zoom"
        source: full
        scale: 1 + 0.35 * rv.p
        opacity: 1 - rv.p * rv.p
        blurEnabled: true
        blurMax: 48
        blur: Math.min(1, rv.p * 1.4)
    }

    // ---- круг: дыра растёт от аватара, край мягкий ----
    Item {
        id: irisMask
        anchors.fill: parent
        visible: false
        layer.enabled: true   // всегда: включённая на ходу (стиль выбирается при вводе пароля) маска до MultiEffect не доходила
        readonly property real maxR: Math.sqrt(Math.pow(Math.max(rv.originX, rv.width - rv.originX), 2)
                                               + Math.pow(Math.max(rv.originY, rv.height - rv.originY), 2)) + 40
        Rectangle {
            readonly property real r: irisMask.maxR * rv.p
            x: rv.originX - r; y: rv.originY - r
            width: 2 * r; height: 2 * r; radius: r
            color: "white"
        }
    }
    MultiEffect {
        anchors.fill: parent
        visible: rv.active && rv.style === "iris"
        source: full
        maskEnabled: true
        maskInverted: true
        maskSource: irisMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.6
    }

    // ---- в остров: прямоугольник экрана сжимается в пилюлю наверху, потом гаснет ----
    Item {
        id: islandMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        readonly property real t: Math.min(1, rv.p / 0.75)
        Rectangle {
            x: rv.lerp(0, rv.islandRect.x, islandMask.t)
            y: rv.lerp(0, rv.islandRect.y, islandMask.t)
            width: rv.lerp(rv.width, rv.islandRect.width, islandMask.t)
            height: rv.lerp(rv.height, rv.islandRect.height, islandMask.t)
            radius: rv.lerp(0, rv.islandRect.height / 2, Math.min(1, islandMask.t * 2.5))
            color: "white"
        }
    }
    MultiEffect {
        anchors.fill: parent
        visible: rv.active && rv.style === "island"
        source: full
        maskEnabled: true
        maskSource: islandMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.2
        opacity: rv.p < 0.75 ? 1 : (1 - rv.p) / 0.25
    }

    // ---- шторки: левая и правая половины разъезжаются ----
    Repeater {
        model: rv.active && rv.style === "curtains" ? 2 : 0
        delegate: ShaderEffectSource {
            required property int index
            readonly property real half: rv.width / 2
            width: half; height: rv.height
            x: index === 0 ? -half * rv.p : half + half * rv.p
            sourceItem: rv.cover
            sourceRect: Qt.rect(index * half, 0, half, rv.height)
            live: false
            // тень на внутреннем краю половины
            Rectangle {
                readonly property bool isL: parent.index === 0
                width: 24; height: parent.height
                x: isL ? parent.width - width : 0
                opacity: Math.min(1, rv.p * 4) * 0.5
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "#000000" }
                }
                rotation: isL ? 0 : 180
            }
        }
    }

    // ---- плитки: волна от центра, каждая сжимается, поворачивается и гаснет ----
    Repeater {
        id: tiles
        readonly property int cols: 10
        readonly property int rows: Math.max(4, Math.round(cols * rv.height / Math.max(1, rv.width)))
        model: rv.active && rv.style === "tiles" ? cols * rows : 0
        delegate: ShaderEffectSource {
            required property int index
            readonly property int cx: index % tiles.cols
            readonly property int cy: Math.floor(index / tiles.cols)
            readonly property real tw: rv.width / tiles.cols
            readonly property real th: rv.height / tiles.rows
            // задержка — по расстоянию от центра (0…1), плитка уходит за 40 % времени
            readonly property real d: Math.min(1, Math.hypot((cx + 0.5) * tw - rv.originX, (cy + 0.5) * th - rv.originY)
                                              / Math.hypot(rv.width / 2, rv.height / 2))
            readonly property real t: Math.max(0, Math.min(1, (rv.p - d * 0.6) / 0.4))
            x: cx * tw; y: cy * th
            width: Math.ceil(tw) + 1; height: Math.ceil(th) + 1
            sourceItem: rv.cover
            sourceRect: Qt.rect(cx * tw, cy * th, width, height)
            live: false
            scale: 1 - t
            rotation: t * ((index % 2) ? 25 : -25)
            opacity: 1 - t * t
        }
    }
}
