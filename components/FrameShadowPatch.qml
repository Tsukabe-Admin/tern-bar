import QtQuick

// One perimeter slice of the Frame look's inward bezel shadow (compiled .frag.qsb).
ShaderEffect {
    id: patch

    property vector4d innerBox: Qt.vector4d(0, 0, 0, 0)
    property vector4d shadowParams: Qt.vector4d(0, 0, 1, 1)
    property vector4d geomParams: Qt.vector4d(0, 0, 0, 0)
    property vector4d topCut: Qt.vector4d(0, 0, 0, 0)
    property vector4d topAttach: Qt.vector4d(0, 0, 0, 0)
    property vector4d botCut: Qt.vector4d(0, 0, 0, 0)

    readonly property vector4d u_patchRect: Qt.vector4d(patch.x, patch.y, patch.width, patch.height)
    readonly property vector4d u_innerBox: patch.innerBox
    readonly property vector4d u_shadow: patch.shadowParams
    readonly property vector4d u_geom: patch.geomParams
    readonly property vector4d u_topCut: patch.topCut
    readonly property vector4d u_topAttach: patch.topAttach
    readonly property vector4d u_botCut: patch.botCut

    visible: patch.width > 0 && patch.height > 0 && patch.geomParams.z > 0
    fragmentShader: Qt.resolvedUrl("../shaders/frame_shadow.frag.qsb")
}
