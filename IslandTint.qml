import QtQuick
import QtQuick.Shapes

// Несколько цветов острова сразу (камера, микрофон, демонстрация экрана, плагины): неподвижный градиент слева
// направо — заливка с лёгким оттенком и обводка в 1 px поверх фона острова. Кладётся первым ребёнком фигуры
// (под содержимое); пока цветов меньше двух, не рисуется — тогда хватает обычных color/border фигуры.
Shape {
    id: tint
    property var colors: []
    property real radius: 0
    readonly property bool on: colors.length > 1
    anchors.fill: parent
    opacity: on ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Prefs.ms(400) } }
    preferredRendererType: Shape.CurveRenderer   // сглаженные дуги без MSAA

    // последние цвета держим, пока гаснем, — иначе градиент пропал бы до конца растворения
    property var shown: []
    onColorsChanged: if (colors.length > 1) shown = colors.map(x => typeof x === "string" ? Qt.color(x) : x)
    readonly property real r: Math.min(radius, height / 2, width / 2)

    // цвет в точке t ∈ [0, 1]: цвета равномерно, между ними — плавный переход
    function at(t, a) {
        var c = shown, n = c.length
        if (n === 0) return "transparent"
        var x = t * (n - 1), i = Math.min(n - 2, Math.floor(x)), f = x - i
        if (n === 1) return Qt.rgba(c[0].r, c[0].g, c[0].b, a)
        var p = c[i], q = c[i + 1]
        return Qt.rgba(p.r + (q.r - p.r) * f, p.g + (q.g - p.g) * f, p.b + (q.b - p.b) * f, a)
    }
    component Grad: LinearGradient {   // inline-компонент не видит id файла — фигура передаётся свойством
        property var src
        property real alpha: 1
        x1: 0; y1: 0; x2: src ? src.width : 0; y2: 0
        GradientStop { position: 0;    color: src ? src.at(0, alpha) : "transparent" }
        GradientStop { position: 0.25; color: src ? src.at(0.25, alpha) : "transparent" }
        GradientStop { position: 0.5;  color: src ? src.at(0.5, alpha) : "transparent" }
        GradientStop { position: 0.75; color: src ? src.at(0.75, alpha) : "transparent" }
        GradientStop { position: 1;    color: src ? src.at(1, alpha) : "transparent" }
    }

    ShapePath {   // заливка: оттенок, как у одного цвета (16 %)
        strokeWidth: -1
        fillGradient: Grad { src: tint; alpha: 0.16 }
        PathRectangle { x: 0; y: 0; width: tint.width; height: tint.height; radius: tint.r }
    }
    ShapePath {   // обводка: кольцо из двух прямоугольников (чётно-нечётная заливка)
        strokeWidth: -1
        fillRule: ShapePath.OddEvenFill
        fillGradient: Grad { src: tint; alpha: 1 }
        PathRectangle { x: 0; y: 0; width: tint.width; height: tint.height; radius: tint.r }
        PathRectangle { x: 1; y: 1; width: Math.max(0, tint.width - 2); height: Math.max(0, tint.height - 2); radius: Math.max(0, tint.r - 1) }
    }
}
