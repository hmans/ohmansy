pragma Singleton
import QtQuick

QtObject {
    // Distinct from QtQuick.Palette, which contains widget color roles.
    property var settings: null
    property bool ready: false
    property bool animationsEnabled: true
    property int transitionDuration: 1000
    property var legacyFrame: [81/255,64/255,95/255]
    property var materialSettings: null
    property real intensity: 0.65
    property var legacyInactive: [37/255,40/255,53/255]
    readonly property var targetPalette: settings || ({atmosphere: [69/255,85/255,108/255], accent: [166/255,132/255,1], companion: [1,210/255,48/255]})
    readonly property var fallback: ({ active_frame: legacyFrame, inactive_frame: legacyInactive,
        surface: [0.12,0.14,0.18], text: [0.95,0.95,0.97], muted_text: [0.68,0.70,0.75],
        ribbon_atmosphere: [0.30,0.36,0.44], ribbon_accent: [0.55,0.39,0.84], ribbon_companion: [0.77,0.56,0.13],
        ribbon_atmosphere_light: [0.60,0.65,0.71], ribbon_accent_light: [0.70,0.58,0.96], ribbon_companion_light: [0.88,0.71,0.32],
        background_top: [0.04,0.06,0.08], background_bottom: [0.09,0.13,0.18],
        background_top_light: [0.92,0.94,0.96], background_bottom_light: [0.81,0.85,0.90], sheen: [0.94,0.95,0.97] })
    readonly property string materialKey: JSON.stringify(materialSettings || fallback)
    property var fromMaterials: fallback
    property var toMaterials: fallback
    property real progress: 1
    readonly property var materials: {
        const result = {};
        for (const key of Object.keys(toMaterials)) {
            const to = toMaterials[key], from = fromMaterials[key] || to;
            result[key] = to.map((v,i) => from[i] + (v-from[i])*progress);
        }
        return result;
    }
    readonly property bool transitioning: fade.running
    readonly property color frameColor: color(materials.active_frame)
    readonly property var primary: materials.ribbon_accent
    readonly property var secondary: materials.ribbon_atmosphere
    readonly property var accent: materials.ribbon_companion
    property NumberAnimation fade: NumberAnimation {
        target: DesktopPalette; property: "progress"; to: 1
        duration: DesktopPalette.transitionDuration; easing.type: Easing.InOutCubic
    }
    onMaterialKeyChanged: {
        const visible = materials;
        fade.stop();
        fromMaterials = visible;
        toMaterials = materialSettings || fallback;
        if (ready && animationsEnabled && transitionDuration > 0) {
            progress = 0;
            fade.start();
        } else progress = 1;
    }
    function finishTransitions() { fade.stop(); progress = 1; }
    onAnimationsEnabledChanged: if (!animationsEnabled) finishTransitions()
    onTransitionDurationChanged: if (transitionDuration === 0) finishTransitions()
    function color(rgb, alpha = 1) { return Qt.rgba(rgb[0], rgb[1], rgb[2], alpha); }
    function frameTint(alpha) { return color(materials.active_frame, alpha); }
    function inactiveTint(alpha) { return color(materials.inactive_frame, alpha); }
    property var presets: null
    readonly property string presetsKey: JSON.stringify(presets || [])
    property var themes: []
    onPresetsKeyChanged: themes = presets || []
    function matches(palette) {
        return ["atmosphere", "accent", "companion"].every(key =>
            palette[key].every((value, index) => Math.abs(value - targetPalette[key][index]) < 0.0001));
    }
    readonly property string currentName: themes.find(theme => matches(theme.palette))?.name || "Custom"
}
