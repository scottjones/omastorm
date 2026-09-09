.pragma library
// The timeline as the surfaces read it (docs/protocol.md, timeline): the
// ticks, the frame whose age the engine reports, and the age of the frame
// on screen. Pure functions shared by the window and the popover.

// The newest complete frame, or null; the sweep in progress does not count.
function newestComplete(frames) {
    for (var i = frames.length - 1; i >= 0; i--) if (frames[i].status === "complete") return frames[i];
    return null;
}

// The age in seconds of the frame on screen, or -1 while nothing can be
// judged. The engine gives the newest complete frame's age, ticking once a
// second; an older frame on screen adds the distance between the two scan
// times, so no local clock is consulted.
function shownAge(frames, scan, ageSeconds) {
    var newest = newestComplete(frames);
    if (!scan || !scan.scanTime || !newest) return -1;
    return Math.max(0, ageSeconds + Math.round((Date.parse(newest.scanTime) - Date.parse(scan.scanTime)) / 1000));
}

// An age as the header says it; `brief` drops the lesser unit for the
// popover's width.
function ago(seconds, brief) {
    var m = Math.floor(seconds / 60);
    if (m < 1) return "just now";
    if (m < 60) return m + " min ago";
    var h = Math.floor(m / 60);
    if (h < 24) return brief ? h + "h ago" : h + "h " + (m % 60) + "m ago";
    var d = Math.floor(h / 24);
    return brief ? d + "d ago" : d + "d " + (h % 24) + "h ago";
}

// Frame ticks and up to three stubs for missing scan intervals.
function slots(frames) {
    var out = [], n = frames.length;
    if (!n) return out;
    var gaps = [];
    for (var i = 1; i < n; i++) gaps.push(Date.parse(frames[i].scanTime) - Date.parse(frames[i - 1].scanTime));
    var sorted = gaps.slice().sort((a, b) => a - b), median = sorted.length ? sorted[Math.floor(sorted.length / 2)] : 0;
    for (var j = 0; j < n; j++) {
        var missing = j > 0 && median > 0 ? Math.min(3, Math.round(gaps[j - 1] / median) - 1) : 0;
        for (var k = 0; k < missing; k++) out.push({ id: "", stub: true, partial: false });
        out.push({ id: frames[j].id, stub: false, partial: frames[j].status === "partial" });
    }
    return out;
}
