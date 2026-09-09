pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Location.js" as Location
import "Keys.js" as KeyMap

QtObject {
    id: session
    // One non-map connection keeps the bar current, including on multiple
    // outputs. Visible maps have separate sockets for their tile rectangles.
    property Engine engine: Engine {}
    property Config config: Config {}
    property Remembered remembered: Remembered {}
    property Theme theme: Theme {}
    property bool windowOpen: false
    property bool initialized: false
    property string treatment: Quickshell.env("OMASTORM_STYLE") || "GLYPHS"
    // The weak-return floor in dBZ, or null for every measured return
    // (DESIGN.md, weak-return floor); config.toml's weak_floor and the `w`
    // key change it, OMASTORM_WEAK outranks the file for captures.
    property var weakFloor: KeyMap.envFloor(Quickshell.env("OMASTORM_WEAK")) !== undefined ? KeyMap.envFloor(Quickshell.env("OMASTORM_WEAK")) : KeyMap.DEFAULT_FLOOR
    property string startupError: ""
    readonly property bool ready: config.ready && remembered.ready
    readonly property string persistError: remembered.error ? remembered.error.toUpperCase() : ""
    // The view (DESIGN.md, location): the camera and where its centre came
    // from. `locationSource` is `config`, `state`, `weather`, or `view`
    // (OMASTORM_VIEW) once a centre is known; `needsLocation` is the
    // onboarding state, true only while no source supplies one.
    property bool hasView: false
    property bool needsLocation: false
    property string placeName: ""
    property string locationSource: ""
    property real centerLat: 0
    property real centerLon: 0
    property real span: Location.DEFAULT_SPAN
    // The radar lock: the station pinned against hand-offs, or none while
    // the nearest station follows the centre, and who asked for it:
    // `config` (locked_radar), `state` (a session choice, remembered), or
    // `nearest` when there is none.
    property string lockId: ""
    property string lockSource: ""
    property string lastConfigLock: ""
    property bool pendingLocationPicker: false
    property var appliedExplicit: null
    signal viewChanged()
    signal locationPickerRequested()

    function requestLocationPicker() {
        pendingLocationPicker = true;
        locationPickerRequested();
    }

    // Every way a centre is chosen lands here: the camera, its span, and the
    // provenance the header names. A placed view ends onboarding.
    function placeView(lat, lon, spanKm, source, name) {
        centerLat = lat;
        centerLon = lon;
        span = Location.clampSpan(spanKm);
        hasView = true;
        needsLocation = false;
        locationSource = source;
        placeName = name || "";
    }

    // The lock as one move: a station pins the radar and `source` says who
    // asked; an empty id releases it to the nearest station.
    function holdLock(id, source) {
        lockId = id || "";
        lockSource = lockId ? source : "nearest";
    }

    // Launch and a change to config.toml resolve the lock the same way: a
    // configured lock wins, else the remembered one, else nearest.
    function resolveLock(rememberedLock) {
        lastConfigLock = Location.configLock(config.values);
        holdLock(lastConfigLock || rememberedLock, lastConfigLock ? "config" : "state");
    }

    function resolve() {
        if (!ready) return;
        var env = Location.envView(Quickshell.env("OMASTORM_VIEW"));
        var explicit = Location.configCenter(config.values);
        var rememberedView = remembered.parsed;
        if (!hasView) {
            var place = Location.resolvePlace(explicit, rememberedView, config.location, env);
            if (place) placeView(place.lat, place.lon, place.span, place.source, place.name);
            else {
                needsLocation = true;
                locationSource = "";
                placeName = "";
            }
            resolveLock(rememberedView.lock);
        }
        // An explicit centre applies again whenever it changes, over any view
        // the session has; removing it leaves the camera where it is.
        if (explicit) {
            var same = appliedExplicit && appliedExplicit.lat === explicit.lat && appliedExplicit.lon === explicit.lon;
            appliedExplicit = explicit;
            if (hasView && !same) placeView(explicit.lat, explicit.lon, span, "config", "");
        } else {
            appliedExplicit = null;
        }
        applyConfigLockChange();
        viewChanged();
    }

    function applyConfigLockChange() {
        if (Location.configLock(config.values) === lastConfigLock) return;
        resolveLock(remembered.lock);
    }

    function persist() {
        if (!hasView) return;
        remembered.snapshot(centerLat, centerLon, span, lockId, placeName);
    }

    function rememberView(lat, lon, spanKm) {
        if (needsLocation) return;
        if (!Location.validPair(lat, lon)) return;
        var next = Location.clampSpan(spanKm);
        if (hasView && centerLat === lat && centerLon === lon && span === next) return;
        centerLat = lat;
        centerLon = lon;
        span = next;
        hasView = true;
        persistTimer.restart();
    }

    // A place from the location picker: the default span, a configured lock
    // kept, any other lock released (DESIGN.md, location).
    function setPlace(lat, lon, name) {
        if (!Location.validPair(lat, lon)) return;
        pendingLocationPicker = false;
        placeView(lat, lon, Location.DEFAULT_SPAN, "state", name);
        holdLock(lockSource === "config" ? Location.configLock(config.values) : "", "config");
        persist();
        viewChanged();
        applyRadar();
    }

    function resetView() {
        var target = Location.resolveReset(Location.configCenter(config.values), config.location);
        if (target) placeView(target.lat, target.lon, Location.DEFAULT_SPAN, target.source, target.name);
        else if (!hasView) {
            requestLocationPicker();
            return;
        } else span = Location.DEFAULT_SPAN;
        persist();
        viewChanged();
        applyRadar();
    }

    // A station from the site picker: locked and centred, the span kept.
    function chooseRadar(id, lat, lon, name) {
        lat = Number(lat);
        lon = Number(lon);
        if (!id || !Location.validPair(lat, lon)) return;
        pendingLocationPicker = false;
        placeView(lat, lon, span, "state", name || id);
        holdLock(id, "state");
        persist();
        viewChanged();
        applyRadar();
    }

    function setLock(id, on) {
        holdLock(on ? id : "", "state");
        persist();
        applyRadar();
    }

    function followNearest(id) {
        holdLock("");
        persist();
        if (!engine.state) return;
        if (engine.state.site.locked) engine.send({type: "lock", enabled: false});
        if (!engine.state.site.follow) engine.send({type: "follow", enabled: true});
        if (id && (engine.state.site.id !== id || engine.state.source !== "live"))
            engine.send({type: "select_site", id: id});
    }

    // Reconcile the engine with the lock and the view: only what differs is
    // sent, so a repeat changes nothing (docs/protocol.md, commands).
    function applyRadar() {
        if (!engine.state || !ready || needsLocation) return;
        var site = engine.state.site;
        if (lockId) {
            if (site.id !== lockId || engine.state.source !== "live")
                engine.send({type: "select_site", id: lockId});
            if (!site.locked) engine.send({type: "lock", enabled: true});
            if (!site.follow) engine.send({type: "follow", enabled: true});
        } else {
            if (site.locked) engine.send({type: "lock", enabled: false});
            if (!site.follow) engine.send({type: "follow", enabled: true});
            if (hasView) engine.send({type: "view_center", lat: centerLat, lon: centerLon});
        }
    }

    function initialize() {
        if (initialized || !engine.state || !ready) return;
        initialized = true;
        resolve();
        applyRadar();
        persist();
    }

    function applyTreatment() {
        var errors = [], wanted = KeyMap.treatment(config.treatment, errors);
        if (!Quickshell.env("OMASTORM_STYLE") && wanted) treatment = wanted;
        if (KeyMap.envFloor(Quickshell.env("OMASTORM_WEAK")) === undefined) weakFloor = KeyMap.weakFloor(config.weakFloor, errors);
    }

    property Timer persistTimer: Timer { interval: 400; onTriggered: session.persist() }
    property Connections engineEvents: Connections {
        target: session.engine
        function onStateChanged() {
            if (!session.engine.state) session.initialized = false;
            else { session.startupError = ""; session.initialize(); }
        }
    }
    property Connections configEvents: Connections {
        target: session.config
        function onReadyChanged() { session.resolve(); session.initialize(); }
        function onValuesChanged() { if (session.initialized) { session.resolve(); session.applyRadar(); } }
        function onLocationChanged() { if (!session.hasView) session.resolve(); if (session.initialized) session.applyRadar(); }
        function onTreatmentChanged() { session.applyTreatment(); }
        function onWeakFloorChanged() { session.applyTreatment(); }
    }
    property Connections rememberedEvents: Connections {
        target: session.remembered
        function onReadyChanged() { session.resolve(); session.initialize(); }
    }
    // The engine bootstrap (run.sh --ensure: install the pinned engine if
    // needed, start or replace the daemon) runs detached, so a plugin reload
    // mid-install cannot kill it: `omarchy plugin add` clones many files and
    // the registry reloads the plugin on each one. While the engine stays
    // unreachable it is retried every 20 s, so a killed or failed attempt
    // recovers on its own. argv, never shell text, since checkout paths may
    // contain spaces; bash will not start in Quickshell's cwd
    // (qrc:/qs-blackhole), so env -C moves it home. Its stderr lands in
    // bootstrap.log beside the socket, and the popover shows the last line
    // while there is no engine.
    readonly property string root: Quickshell.env("OMASTORM_ROOT") || Quickshell.env("HOME") + "/.config/omarchy/plugins/com.omastorm.radar"
    readonly property string bootstrapLog: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omastorm/bootstrap.log"
    function bootstrap() {
        Quickshell.execDetached(["env", "-C", Quickshell.env("HOME"), "OMASTORM_BOOTSTRAP_LOG=" + bootstrapLog, "bash", root + "/run.sh", "--ensure"]);
    }
    property Timer bootstrapRetry: Timer { interval: 20000; repeat: true; running: !session.engine.state; onTriggered: session.bootstrap() }
    property FileView bootstrapLogFile: FileView {
        path: session.bootstrapLog
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { var lines = text().trim().split("\n"); session.startupError = session.engine.state ? "" : lines[lines.length - 1]; }
    }
    Component.onCompleted: { applyTreatment(); resolve(); bootstrap(); }
}
