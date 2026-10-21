import QtQuick
import QtQuick.Shapes

// Общий контур правой капсулы бара и меню трея: меню свисает из капсулы каплей, стык — вогнутыми
// скруглениями. Координаты — от левого верхнего угла капсулы. Бар и меню — разные окна, а фон
// полупрозрачный, поэтому наложить их нельзя (на перекрытии темнее): оба рисуют ЭТОТ ЖЕ контур,
// и каждое окно показывает свою половину — бар обрезает всё ниже капсулы, окно меню начинается
// ровно от её низа. Обводка — по середине пикселя (+0.5), как внутренняя border у Rectangle.
Shape {
    id: sh
    property real capW: 100           // капсула
    property real capH: 32
    property real capR: 16
    property real menuL: 0            // меню: левый и правый край (от левого края капсулы)
    property real menuR: 0
    property real menuH: 0            // текущая высота меню (0 — капсула как обычно)
    property real menuRadius: 16
    property real fillet: 12          // радиус вогнутого скругления на стыке
    property color fill: Theme.backgroundBar
    property color stroke: Theme.outline

    readonly property real r: Math.max(0, Math.min(capR, capH / 2) - 0.5)
    readonly property real ty: 0.5
    readonly property real lx: 0.5
    readonly property real rx: capW - 0.5
    readonly property real by: capH - 0.5                    // низ капсулы
    readonly property real mb: capH + Math.max(0, menuH) - 0.5   // низ меню
    // меню закрыто — его «края» на прямом участке низа: иначе линия низа уходила под скругления углов
    // капсулы (menuL = menuR = 0 → до x = -0.5) и в углах была видна прямая полоска
    readonly property bool closed: menuH <= 0 || menuR <= menuL
    readonly property real ml: closed ? lx + r : menuL + 0.5
    readonly property real mr: closed ? lx + r : menuR - 0.5
    readonly property real f: Math.max(0, Math.min(fillet, menuH))
    readonly property real mR: Math.max(0, Math.min(menuRadius, menuH / 2, (mr - ml) / 2))

    width: capW
    height: capH + Math.max(0, menuH)
    preferredRendererType: Shape.CurveRenderer   // сглаженные дуги без MSAA

    ShapePath {
        fillColor: sh.fill
        strokeColor: sh.stroke
        strokeWidth: 1
        joinStyle: ShapePath.RoundJoin
        startX: sh.lx + sh.r; startY: sh.ty
        PathLine { x: sh.rx - sh.r; y: sh.ty }
        PathArc { x: sh.rx; y: sh.ty + sh.r; radiusX: sh.r; radiusY: sh.r }
        PathLine { x: sh.rx; y: sh.by - sh.r }
        PathArc { x: sh.rx - sh.r; y: sh.by; radiusX: sh.r; radiusY: sh.r }
        // правый стык: вогнутая дуга вниз, в меню
        PathLine { x: sh.mr + sh.f; y: sh.by }
        PathArc { x: sh.mr; y: sh.by + sh.f; radiusX: sh.f; radiusY: sh.f; direction: PathArc.Counterclockwise }
        PathLine { x: sh.mr; y: sh.mb - sh.mR }
        PathArc { x: sh.mr - sh.mR; y: sh.mb; radiusX: sh.mR; radiusY: sh.mR }
        PathLine { x: sh.ml + sh.mR; y: sh.mb }
        PathArc { x: sh.ml; y: sh.mb - sh.mR; radiusX: sh.mR; radiusY: sh.mR }
        // левый стык: обратно вверх, в низ капсулы
        PathLine { x: sh.ml; y: sh.by + sh.f }
        PathArc { x: sh.ml - sh.f; y: sh.by; radiusX: sh.f; radiusY: sh.f; direction: PathArc.Counterclockwise }
        PathLine { x: sh.lx + sh.r; y: sh.by }
        PathArc { x: sh.lx; y: sh.by - sh.r; radiusX: sh.r; radiusY: sh.r }
        PathLine { x: sh.lx; y: sh.ty + sh.r }
        PathArc { x: sh.lx + sh.r; y: sh.ty; radiusX: sh.r; radiusY: sh.r }
    }
}
