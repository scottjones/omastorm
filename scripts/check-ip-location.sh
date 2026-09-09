#!/usr/bin/env bash
# Exercise the actual shared session and Engine parser with private replies.
# No network, personal configuration, shell bootstrap, or shared daemon.
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d /tmp/omastorm-ip-check.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp -r ui "$scratch/ui"
sed -i '/Quickshell.execDetached(/c\        return;' "$scratch/ui/PluginSession.qml"
sed -i 's/connected: true/connected: false/; /running: engine.socket/c\        running: false' "$scratch/ui/Engine.qml"
cat > "$scratch/ui/Test.qml" <<'QML'
import QtQuick
import Quickshell
import "Location.js" as Location
ShellRoot {
    id: test
    Engine {
        id: fake
        property var sent: []
        function send(command) { sent = sent.concat([command]); }
    }
    function assertThat(ok, why) { if (!ok) throw new Error(why); }
    function fresh(values, saved, weather, source) {
        var s = PluginSession;
        fake.state = null;
        fake.location = null;
        fake.locationRequested = false;
        fake.locationPending = false;
        fake.locationError = "";
        fake.locationTimeout.stop();
        s.initialized = false;
        s.hasView = false;
        s.needsLocation = false;
        s.ipLocationDismissed = false;
        s.appliedExplicit = null;
        s.config.values = values;
        s.remembered.parsed = Location.parseState(saved);
        s.config.location = weather;
        fake.sent = [];
        fake.state = {source: source || "live", site: {id: "", locked: false, follow: true}};
        s.initialize();
    }
    function countLookups() { return fake.sent.filter(c => c.type === "locate_home").length; }
    function reply() { fake.receive(JSON.stringify({type:"location", v:1, name:"Stamford", lat:41.05, lon:-73.54})); }
    Timer {
        interval: 10; running: true; repeat: true
        onTriggered: {
            var s = PluginSession;
            if (!s.ready) return;
            stop();
            try {
                s.engine = fake;
                fresh({ip_location:true}, "", null);
                assertThat(s.locating && s.needsLocation && countLookups() === 1, "fresh lookup");
                s.resolve();
                assertThat(countLookups() === 1, "duplicate lookup");
                reply();
                assertThat(s.hasView && !s.needsLocation && s.locationSource === "ip", "IP view");
                assertThat(s.centerLat === 41.05 && s.centerLon === -73.54, "IP coordinates");
                assertThat(s.remembered.lat === 41.05 && s.remembered.lon === -73.54, "remember IP view");
                assertThat(fake.sent.some(c => c.type === "view_center" && c.lat === 41.05), "nearest radar follows IP center");
                fresh({ip_location:true}, JSON.stringify(s.remembered.parsed), null);
                assertThat(s.locationSource === "state" && countLookups() === 0, "reopen remembered IP without lookup");
                fresh({ip_location:true, center_lat:30, center_lon:-81}, '{"lat":35,"lon":-97}', {lat:36,lon:-79});
                reply();
                assertThat(s.locationSource === "config" && s.centerLat === 30 && countLookups() === 0, "explicit precedence");
                fresh({ip_location:true}, '{"lat":35,"lon":-97}', {lat:36,lon:-79});
                reply();
                assertThat(s.locationSource === "state" && s.centerLat === 35 && countLookups() === 0, "state precedence");
                fresh({ip_location:true}, "", {lat:36,lon:-79});
                reply();
                assertThat(s.locationSource === "weather" && s.centerLat === 36 && countLookups() === 0, "weather precedence");
                fresh({ip_location:true, locked_radar:"KTLX"}, "", null);
                reply();
                assertThat(s.lockId === "KTLX" && s.lockWanted && s.centerLat === 41.05, "configured lock independent of IP center");
                fresh({ip_location:true}, "", null);
                s.setPlace(30,-81,"Picked"); reply();
                assertThat(s.centerLat === 30 && s.placeName === "Picked", "late reply after picker choice");
                fresh({ip_location:true}, "", null);
                s.chooseRadar("KTLX",35,-97,"Radar"); reply();
                assertThat(s.centerLat === 35 && s.lockId === "KTLX", "late reply after radar choice");
                fresh({ip_location:true}, "", null);
                s.userNavigated(36,-98,170); reply();
                assertThat(s.centerLat === 36 && s.span === 170 && !s.needsLocation, "late reply after navigation");
                fresh({ip_location:true}, "", null);
                s.requestLocationPicker(); reply();
                assertThat(s.needsLocation && !s.hasView && !s.locating, "manual picker interrupts lookup");
                fresh({ip_location:true}, "", null);
                fake.receive('{"type":"error","v":1,"command":"locate_home","message":"unavailable"}');
                assertThat(s.needsLocation && !s.locating, "failure leaves onboarding available");
                fresh({ip_location:false}, "", null); reply();
                assertThat(s.needsLocation && countLookups() === 0, "opt out");
                fresh({}, "", null);
                assertThat(s.needsLocation && countLookups() === 0, "isolated config does not opt in");
                fresh({ip_location:true}, "", null, "archived"); reply();
                assertThat(s.needsLocation && countLookups() === 0, "archive never locates");
                assertThat(s.config.parseLocation('{"latitude":null,"longitude":null}') === null, "null weather is not zero");
                assertThat(Location.configErrors({ip_location:"yes"}).length === 1, "invalid preference is named");
                fresh({ip_location:true}, "", null);
                fake.locationTimeout.interval = 1;
                timeoutCheck.start();
            } catch (e) { console.error(e); Qt.quit(); }
        }
    }
    Timer {
        id: timeoutCheck; interval: 30
        onTriggered: {
            if (PluginSession.needsLocation && !PluginSession.locating && fake.locationError)
                console.log("IP_LOCATION_PASSED");
            else console.error("old-engine timeout did not restore onboarding");
            Qt.quit();
        }
    }
}
QML
OMASTORM_CONFIG="$scratch/empty.toml" OMASTORM_STATE="$scratch/state.json" \
  XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen \
  timeout 15 quickshell -p "$scratch/ui/Test.qml" > "$scratch/log" 2>&1 || { cat "$scratch/log"; exit 1; }
cat "$scratch/log"
rg -q IP_LOCATION_PASSED "$scratch/log"
! rg -q 'ReferenceError|TypeError|Binding loop|Unable to assign' "$scratch/log"
