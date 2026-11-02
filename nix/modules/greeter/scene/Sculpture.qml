import QtQuick
import QtQuick3D
import QtQuick3D.Helpers

View3D {
    id: scene
    property bool moving: true
    // Render the background at logical resolution; keep the form at native DPI.
    readonly property real renderScale: Math.min(1, 1600 / Math.max(1, width), 1000 / Math.max(1, height))
    explicitTextureWidth: Math.max(1, Math.round(width * renderScale))
    explicitTextureHeight: Math.max(1, Math.round(height * renderScale))
    environment: SceneEnvironment {
        backgroundMode: SceneEnvironment.Color
        clearColor: "#171a21"
        antialiasingMode: SceneEnvironment.MSAA
        antialiasingQuality: SceneEnvironment.Medium
    }
    camera: PerspectiveCamera {
        z: 850
        fieldOfView: 42
        clipNear: 10
        clipFar: 2000
    }
    DirectionalLight {
        eulerRotation: Qt.vector3d(-35, -35, 0)
        color: "#e0d4ef"
        brightness: 1.2
        ambientColor: "#303240"
    }
    DirectionalLight {
        eulerRotation: Qt.vector3d(20, 130, 30)
        color: "#739fb9"
        brightness: 1.5
    }
    DirectionalLight {
        eulerRotation: Qt.vector3d(60, 25, -20)
        color: "#c4a7e7"
        brightness: 0.5
    }
    Node {
        id: orbit
        x: 210
        eulerRotation.x: 55
        eulerRotation.z: -25
        Model {
            geometry: TorusGeometry { radius: 145; tubeRadius: 38; rings: 128; segments: 32 }
            scale: Qt.vector3d(1, 1.3, 1)
            materials: PrincipledMaterial {
                baseColor: "#9281b0"
                metalness: 0.25
                roughness: 0.32
            }
        }
        Model {
            geometry: TorusGeometry { radius: 145; tubeRadius: 20; rings: 128; segments: 24 }
            eulerRotation: Qt.vector3d(65, 35, 15)
            materials: PrincipledMaterial {
                baseColor: "#49778c"
                metalness: 0.35
                roughness: 0.38
            }
        }
        NumberAnimation on eulerRotation.y {
            from: -25; to: 335; duration: 120000
            loops: Animation.Infinite
            paused: !scene.moving
        }
    }
}
