import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var outputs: Pipewire.nodes.values.filter(node => node.audio && node.isSink && !node.isStream)
    readonly property bool available: !!sink && !!sink.audio && sink.ready
    readonly property real volume: available ? sink.audio.volume : 0
    readonly property bool muted: available && sink.audio.muted
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    function label(node): string { return node ? node.nickname || node.description || node.name : "No output connected"; }
    function setVolume(value: real): void {
        if (available && Number.isFinite(value)) sink.audio.volume = Math.max(0, Math.min(1, value));
    }
    function adjust(delta: real): void { setVolume(volume + delta); }
    function toggleMute(): void { if (available) sink.audio.muted = !sink.audio.muted; }
    function selectOutput(node): void {
        if (outputs.indexOf(node) >= 0) Pipewire.preferredDefaultAudioSink = node;
    }
}
