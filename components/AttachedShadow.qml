import QtQuick

// Inward drop shadow for top-attached drawers/launcher, bottom-docked OSDs,
// and fullscreen floating OSD capsules in the Frame look (compiled .frag.qsb).
ShaderEffect {
    id: patch

    property vector4d attachRect: Qt.vector4d(0, 0, 0, 0)
    property vector4d attachRadii: Qt.vector4d(0, 0, 0, 0)
    property vector4d innerBox: Qt.vector4d(0, 0, 0, 0)
    property vector4d shadowParams: Qt.vector4d(0, 0, 1, 1)
    property vector4d geomParams: Qt.vector4d(0, 0, 0, 0)
    property vector4d cutSpan: Qt.vector4d(0, 0, 0, 0)
    property real attachOpacity: 1.0

    readonly property vector4d u_patchRect: Qt.vector4d(patch.x, patch.y, patch.width, patch.height)
    readonly property vector4d u_attachRect: patch.attachRect
    readonly property vector4d u_attachRadii: patch.attachRadii
    readonly property vector4d u_innerBox: patch.innerBox
    readonly property vector4d u_shadow: patch.shadowParams
    readonly property vector4d u_geom: patch.geomParams
    readonly property vector4d u_cut: Qt.vector4d(
        patch.cutSpan.x, patch.cutSpan.y, patch.cutSpan.z, patch.attachOpacity)

    visible: patch.width > 0 && patch.height > 0 && patch.geomParams.z > 0
    fragmentShader: Qt.resolvedUrl("../shaders/attached_shadow.frag.qsb")
}
