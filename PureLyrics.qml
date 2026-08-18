import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    property string navidromeUrl: pluginData.navidromeUrl ?? ""
    property string navidromeUser: pluginData.navidromeUser ?? ""
    property string navidromePassword: pluginData.navidromePassword ?? ""
    property bool cachingEnabled: pluginData.cachingEnabled ?? true

    // Display customization
    readonly property real fontSize: (pluginData.fontSize ?? 22)
    readonly property int lineCount: parseInt(pluginData.lineCount ?? "3")
    readonly property string textAlign: (pluginData.textAlign ?? "center")
    readonly property int scrollOffset: parseInt(pluginData.scrollOffset ?? "0")   // ms, + earlier - later

    // Player selection
    readonly property string preferredPlayer: (pluginData.preferredPlayer ?? "auto")
    readonly property bool filterDuplicates: (pluginData.filterDuplicates ?? true)

    // Accent color
    readonly property string colorMode: (pluginData.colorMode ?? "primary")
    readonly property var customColor: (pluginData.customColor ?? Theme.primary)

    // Background
    readonly property real backgroundOpacity: (pluginData.backgroundOpacity ?? 0) / 100
    readonly property real borderOpacity: (pluginData.borderOpacity ?? 100) / 100

    readonly property color accentColor: {
        if (root.colorMode === "secondary") return Theme.secondary;
        if (root.colorMode === "custom" && root.customColor) {
            if (typeof root.customColor === "string") return root.customColor;
            if (root.customColor.valid) return root.customColor;
        }
        return Theme.primary;
    }

    // ── MPRIS active player selection (preferred + dedup) ──
    readonly property var playersList: Mpris.players.values

    readonly property MprisPlayer activePlayer: {
        if (!root.playersList || root.playersList.length === 0) return null;

        // Deduplicate by identity/desktop entry
        let pool = root.playersList;
        if (root.filterDuplicates) {
            const seenIdentities = {};
            const dedup = [];
            for (let i = 0; i < pool.length; i++) {
                const p = pool[i];
                const key = ((p.identity || "") + "|" + (p.desktopEntry || "")).toLowerCase();
                if (!seenIdentities[key]) {
                    seenIdentities[key] = true;
                    dedup.push(p);
                }
            }
            pool = dedup;
        }

        // Preferred player match
        if (root.preferredPlayer !== "auto" && root.preferredPlayer !== "") {
            for (let i = 0; i < pool.length; i++) {
                const p = pool[i];
                const identity = (p.identity || "").toLowerCase();
                const desktopEntry = (p.desktopEntry ? String(p.desktopEntry) : "").toLowerCase();
                if (identity.includes(root.preferredPlayer.toLowerCase()) || desktopEntry.includes(root.preferredPlayer.toLowerCase())) {
                    return p;
                }
            }
        }

        // Browsers expose video/tab MPRIS which is not music — rank them last.
        const browserHints = ["brave", "chromium", "chrome", "firefox", "zen", "browser", "electron", "edge", "vivaldi", "opera"];
        function isBrowser(p) {
            const ident = ((p.identity || "") + " " + (p.desktopEntry || "")).toLowerCase();
            return browserHints.some(h => ident.includes(h));
        }

        // 1. Playing non-browser player (actual music)
        for (let i = 0; i < pool.length; i++) {
            const p = pool[i];
            if (p && p.isPlaying && !isBrowser(p)) return p;
        }

        // 2. Any non-browser player (music player, even if paused)
        for (let i = 0; i < pool.length; i++) {
            const p = pool[i];
            if (p && !isBrowser(p)) return p;
        }

        // 3. Playing browser (video) — only if no music player exists
        for (let i = 0; i < pool.length; i++) {
            const p = pool[i];
            if (p && p.isPlaying) return p;
        }

        return pool[0] ?? null;
    }

    property var allPlayers: MprisController.availablePlayers

    readonly property var sourcePriority: {
        var raw = [
            pluginData.source1 ?? "lrclib",
            pluginData.source2 ?? "lrcapi",
            pluginData.source3 ?? "musixmatch",
            pluginData.source4 ?? "navidrome"
            ];

        var seen = ({}), out = []
        for (var v of raw) {
            if (v && !seen[v]) {
                seen[v] = true;
                out.push(_sourceToEnum(v))
            }
        }
        return out
    }

    // -------------------------------------------------------------------------
    // Enum namespaces
    // -------------------------------------------------------------------------

    // Chip-visible statuses for navidromeStatus, lrclibStatus, and cacheStatus.
    // Values are globally unique so all three properties share one _chipMeta map.
    QtObject {
        id: status
        readonly property int none: 0
        readonly property int searching: 1
        readonly property int found: 2
        readonly property int notFound: 3
        readonly property int error: 4
        readonly property int skippedConfig: 5
        readonly property int skippedFound: 6
        readonly property int skippedPlain: 7
        readonly property int cacheHit: 11
        readonly property int cacheMiss: 12
        readonly property int cacheDisabled: 13
    }

    // Lyrics-fetch lifecycle.
    QtObject {
        id: lyricState
        readonly property int idle: 0
        readonly property int loading: 1
        readonly property int synced: 2
        readonly property int notFound: 3
    }

    // Lyrics sources.
    QtObject {
        id: lyricSrc
        readonly property int none: 0
        readonly property int navidrome: 1
        readonly property int lrclib: 2
        readonly property int cache: 3
        readonly property int musixmatch: 4
        readonly property int lrcapi: 5
    }

    function _sourceToEnum(source) {
        switch (source) {
        case "navidrome":   return lyricSrc.navidrome
        case "lrclib":      return lyricSrc.lrclib
        case "cache":       return lyricSrc.cache
        case "musixmatch":  return lyricSrc.musixmatch
        case "lrcapi":      return lyricSrc.lrcapi
        default:            return lyricSrc.none
        }
    }

    // -------------------------------------------------------------------------
    // Lyrics state
    // -------------------------------------------------------------------------

    property var lyricsLines: []
    property int currentLineIndex: -1
    property bool lyricsLoading: lyricStatus === lyricState.loading
    property string _lastFetchedTrack: ""
    property string _lastFetchedArtist: ""
    property var _cancelActiveFetch: null

    // Chip status properties
    property int navidromeStatus: status.none
    property int lrclibStatus: status.none
    property int lrcapiStatus: status.none
    property int musixmatchStatus: status.none
    property int cacheStatus: status.none

    // Fetch state and source
    property int lyricStatus: lyricState.idle
    property int lyricSource: lyricSrc.none

    // ── Player lock ──
    // Once lyrics are fetched from a player, we lock onto it so other MPRIS
    // players (e.g. a browser playing a video) cannot hijack title/position.
    property var _lockedPlayer: null

    // The player whose lyrics we are actually showing.
    readonly property var lyricPlayer: {
        if (_lockedPlayer && root.playersList.includes(_lockedPlayer))
            return _lockedPlayer;
        return activePlayer;
    }

    function _releaseLockIfStopped() {
        if (_lockedPlayer && _lockedPlayer.playbackState === MprisPlaybackState.Stopped)
            _lockedPlayer = null;
    }

    // Track current song info (from the locked player to stay stable)
    property string currentTitle: lyricPlayer?.trackTitle ?? ""
    property string currentArtist: lyricPlayer?.trackArtist ?? ""
    property string currentAlbum: lyricPlayer?.trackAlbum ?? ""
    property real currentDuration: lyricPlayer?.length ?? 0

    // Current lyric line for bar pill display
    property string currentLyricText: {
        if (lyricsLoading)
            return "Searching lyrics…";
        if (lyricsLines.length > 0 && currentLineIndex >= 0)
            return lyricsLines[currentLineIndex].text || "♪ ♪ ♪";
        if (currentTitle)
            return currentTitle;
        return "No lyrics";
    }

    property bool _configValid: navidromeUrl !== "" && navidromeUser !== "" && navidromePassword !== ""

    on_ConfigValidChanged: {
        console.info("[PureLyrics] Navidrome configured: " + (_configValid ? "yes (" + navidromeUrl + ")" : "no"));
        if (root.lyricPlayer && currentTitle)
            fetchDebounceTimer.restart();
    }

    // Debounce timer — avoids double-fetch when title and artist change simultaneously
    Timer {
        id: fetchDebounceTimer
        interval: 300
        onTriggered: root.fetchLyricsIfNeeded()
    }
    onCurrentTitleChanged: fetchDebounceTimer.restart()
    onCurrentArtistChanged: fetchDebounceTimer.restart()

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _resetLyricsState() {
        lyricsLines = [];
        currentLineIndex = -1;
        navidromeStatus = status.none;
        lrclibStatus = status.none;
        lrcapiStatus = status.none;
        musixmatchStatus = status.none;
        cacheStatus = status.none;
        lyricStatus = lyricState.loading;
        lyricSource = lyricSrc.none;
        _advanceChain = null;
    }

    // Called by a source handler when it finishes. found === true means synced
    // lyrics were stored and the chain stops here; found === false advances to
    // the next source in priority order.
    property var _advanceChain: null

    function _sourceDone(found) {
        var next = root._advanceChain;
        root._advanceChain = null;
        if (next)
            next(found);
    }

    // Maps a lyricSrc enum to its chip-status property.
    function _setSourceStatus(source, statusVal) {
        switch (source) {
        case lyricSrc.navidrome:   navidromeStatus = statusVal;  break;
        case lyricSrc.lrclib:      lrclibStatus = statusVal;     break;
        case lyricSrc.lrcapi:      lrcapiStatus = statusVal;     break;
        case lyricSrc.musixmatch:  musixmatchStatus = statusVal; break;
        }
    }

    // Reads the current chip-status for a source enum. Used by the popout cards;
    function _sourceStatus(source) {
        switch (source) {
        case lyricSrc.navidrome:   return navidromeStatus;
        case lyricSrc.lrclib:      return lrclibStatus;
        case lyricSrc.lrcapi:      return lrcapiStatus;
        case lyricSrc.musixmatch:  return musixmatchStatus;
        case lyricSrc.cache:       return cacheStatus;
        default:                   return status.none;
        }
    }

    // Display metadata (icon + label) for a source enum.
    function _sourceMeta(source) {
        switch (source) {
        case lyricSrc.navidrome:   return { icon: "cloud",         label: "navidrome"  };
        case lyricSrc.lrclib:      return { icon: "library_music", label: "lrclib"     };
        case lyricSrc.lrcapi:      return { icon: "Genres",        label: "lrcapi"     };
        case lyricSrc.musixmatch:  return { icon: "music_note",    label: "musixmatch" };
        case lyricSrc.cache:       return { icon: "cached",        label: "cache"      };
        default:                   return { icon: "help",          label: "unknown"    };
        }
    }

    // -------------------------------------------------------------------------
    // Cache helpers
    // -------------------------------------------------------------------------

    function _fnv1a32(str) {
        var hash = 0x811c9dc5;
        for (var i = 0; i < str.length; i++) {
            hash = ((hash ^ str.charCodeAt(i)) * 0x01000193) >>> 0;
        }
        return ("00000000" + hash.toString(16)).slice(-8);
    }

    function _cacheKey(title, artist) {
        return _fnv1a32((title + "\x00" + artist).toLowerCase());
    }

    readonly property string _cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache") || "") + "/dms-plugin-purelyrics"

    function _cacheFilePath(title, artist) {
        return _cacheDir + "/" + _cacheKey(title, artist) + ".json";
    }

    // Static one-shot timer for XHR request timeouts
    Timer {
        id: xhrTimeoutTimer
        repeat: false
        property var onTimeout: null
        onTriggered: if (onTimeout)
            onTimeout()
    }

    // Static one-shot timer for retry delays
    Timer {
        id: xhrRetryTimer
        repeat: false
        property var onRetry: null
        onTriggered: if (onRetry)
            onRetry()
    }

    // Cache directory creation
    property bool _cacheDirReady: false

    Process {
        id: mkdirProcess
        command: ["mkdir", "-p", root._cacheDir]
        running: false
    }

    function _ensureCacheDir() {
        if (_cacheDirReady)
            return;
        _cacheDirReady = true;
        mkdirProcess.running = true;
    }

    // Cache read using FileView
    Component {
        id: cacheReaderComponent
        FileView {
            property var callback
            blockLoading: true
            preload: true
            onLoaded: {
                try {
                    callback(JSON.parse(text()));
                } catch (e) {
                    callback(null);
                }
                destroy();
            }
            onLoadFailed: {
                callback(null);
                destroy();
            }
        }
    }

    function readFromCache(title, artist, callback) {
        cacheReaderComponent.createObject(root, {
            path: _cacheFilePath(title, artist),
            callback: callback
        });
    }

    // Cache write using FileView
    Component {
        id: cacheWriterComponent
        FileView {
            property string cTitle
            property string cArtist
            blockWrites: false
            atomicWrites: true
            onSaved: {
                console.info("[PureLyrics] Cache: written for \"" + cTitle + "\" by " + cArtist + " (" + path + ")");
                destroy();
            }
            onSaveFailed: {
                console.warn("[PureLyrics] Cache: failed to write for \"" + cTitle + "\"");
                destroy();
            }
        }
    }

    function writeToCache(title, artist, lines, source) {
        _ensureCacheDir();
        var writer = cacheWriterComponent.createObject(root, {
            path: _cacheFilePath(title, artist),
            cTitle: title,
            cArtist: artist
        });
        writer.setText(JSON.stringify({
            lines: lines,
            source: source
        }));
    }

    // -------------------------------------------------------------------------
    // Fetch orchestration
    // -------------------------------------------------------------------------

    function fetchLyricsIfNeeded() {
        var player = root.activePlayer;
        if (!player)
            return;

        // Lock onto this player so browsers/video players can't hijack it.
        root._lockedPlayer = player;

        if (!currentTitle)
            return;

        if (currentTitle === _lastFetchedTrack && currentArtist === _lastFetchedArtist)
            return;

        // Cancel any in-flight XHR before starting fresh
        if (_cancelActiveFetch) {
            _cancelActiveFetch();
            _cancelActiveFetch = null;
        }

        _lastFetchedTrack = currentTitle;
        _lastFetchedArtist = currentArtist;
        _resetLyricsState();

        console.info("[PureLyrics] ▶ Track changed: \"" + currentTitle + "\" by " + currentArtist + (currentAlbum ? " [" + currentAlbum + "]" : ""));

        var capturedTitle = currentTitle;
        var capturedArtist = currentArtist;

        console.info("[PureLyrics] Sources: " + root.sourcePriority);

        // Walk sourcePriority in priority order, one source at a time. Each
        // source calls _sourceDone(found): found === true stops the chain (lyrics
        // were stored), found === false advances to the next source.
        function _realFetch() {
            var sources = root.sourcePriority;
            var i = 0;

            function step() {
                // Track changed mid-chain — abandon quietly.
                if (capturedTitle !== root._lastFetchedTrack || capturedArtist !== root._lastFetchedArtist)
                    return;

                if (i >= sources.length) {
                    // Every source exhausted without synced lyrics.
                    root.lyricStatus = lyricState.notFound;
                    root._cancelActiveFetch = null;
                    console.info("[PureLyrics] ✗ No synced lyrics from any source");
                    return;
                }

                var source = sources[i++];
                root._advanceChain = function (found) {
                    if (found) {
                        root._cancelActiveFetch = null;
                        for (var j = i; j < sources.length; j++)
                            root._setSourceStatus(sources[j], status.skippedFound);
                        return;
                    }
                    step();
                };

                console.info("[PureLyrics] Source: " + source);
                switch (source) {
                case lyricSrc.musixmatch:  root._fetchFromMusixmatch(capturedTitle, capturedArtist); break;
                case lyricSrc.lrclib:      root._fetchFromLrclib(capturedTitle, capturedArtist);     break;
                case lyricSrc.navidrome:   root._fetchFromNavidrome(capturedTitle, capturedArtist);  break;
                case lyricSrc.lrcapi:      root._fetchFromLrcApi(capturedTitle, capturedArtist);     break;
                default:                   root._sourceDone(false);                                  break;
                }
            }

            step();
        }

        if (cachingEnabled) {
            readFromCache(capturedTitle, capturedArtist, function (cached) {
                // Guard: track may have changed while the file read was in progress
                if (capturedTitle !== root._lastFetchedTrack || capturedArtist !== root._lastFetchedArtist)
                    return;
                if (cached && cached.lines && cached.lines.length > 0) {
                    root.lyricsLines = cached.lines;
                    root.lyricStatus = lyricState.synced;
                    root.lyricSource = cached.source > 0 ? cached.source : lyricSrc.cache;
                    root.cacheStatus = status.cacheHit;
                    // Mark only the selected live sources as skipped (cache served it).
                    for (var s of root.sourcePriority)
                        root._setSourceStatus(s, status.skippedFound);
                    console.info("[PureLyrics] ✓ Cache: lyrics loaded for \"" + capturedTitle + "\" (" + cached.lines.length + " lines)");
                    return;
                }
                root.cacheStatus = status.cacheMiss;
                _realFetch();
            });
        } else {
            cacheStatus = status.cacheDisabled;
            _realFetch();
        }
    }

    // -------------------------------------------------------------------------
    // XMLHttpRequest helper
    // -------------------------------------------------------------------------

    function _xhrGet(url, timeoutMs, onSuccess, onError, customHeaders) {
        var retriesLeft = 2;
        var retryDelay = 3000;
        var attempt = 0;
        var cancelled = false;
        var currentXhr = null;

        function _attempt() {
            attempt++;
            currentXhr = new XMLHttpRequest();
            var done = false;

            xhrTimeoutTimer.stop();
            xhrTimeoutTimer.interval = timeoutMs;
            xhrTimeoutTimer.onTimeout = function () {
                if (!done && !cancelled) {
                    done = true;
                    currentXhr.abort();
                    _retry("timeout");
                }
            };
            xhrTimeoutTimer.start();

            currentXhr.onreadystatechange = function () {
                if (currentXhr.readyState !== XMLHttpRequest.DONE || done || cancelled)
                    return;
                done = true;
                xhrTimeoutTimer.stop();
                if (currentXhr.status === 0) {
                    _retry("network error (status 0)");
                    return;
                }
                var responseBody = (currentXhr.responseText || "").trim();
                if (responseBody.length === 0) {
                    _retry("empty response (HTTP " + currentXhr.status + ")");
                    return;
                }
                onSuccess(currentXhr.responseText, currentXhr.status);
            };
            currentXhr.open("GET", url);
            if (customHeaders) {
                for (var key in customHeaders)
                    currentXhr.setRequestHeader(key, customHeaders[key]);
            } else {
                currentXhr.setRequestHeader("User-Agent", "DankMaterialShell PureLyrics/1.0.0");
                currentXhr.setRequestHeader("Accept", "application/json");
            }
            currentXhr.send();
        }

        function _retry(errMsg) {
            if (cancelled)
                return;
            if (retriesLeft > 0) {
                retriesLeft--;
                console.warn("[PureLyrics] _xhrGet: " + errMsg + " — retrying (attempt " + (attempt + 1) + ", " + retriesLeft + " left): " + url);
                xhrRetryTimer.stop();
                xhrRetryTimer.interval = retryDelay;
                xhrRetryTimer.onRetry = _attempt;
                xhrRetryTimer.start();
            } else {
                onError(errMsg);
            }
        }

        _attempt();

        // Return a cancel function the caller can invoke to abort the entire chain
        return function cancel() {
            cancelled = true;
            xhrTimeoutTimer.stop();
            xhrRetryTimer.stop();
            if (currentXhr)
                currentXhr.abort();
            console.info("[PureLyrics] ⊘ XHR cancelled: " + url);
        };
    }

    // -------------------------------------------------------------------------
    // Navidrome fetch
    // -------------------------------------------------------------------------

    // Builds a Navidrome REST URL with common auth params appended
    function _navidromeUrl(endpoint, extraParams) {
        var base = navidromeUrl.replace(/\/+$/, "") + "/rest/" + endpoint;
        var auth = "u=" + encodeURIComponent(navidromeUser) + "&p=" + encodeURIComponent(navidromePassword) + "&v=1.16.1&c=DankMaterialShell&f=json";
        return base + "?" + (extraParams ? extraParams + "&" : "") + auth;
    }

    function _fetchFromNavidrome(expectedTitle, expectedArtist) {
        if (!_configValid) {
            navidromeStatus = status.skippedConfig;
            console.info("[PureLyrics] Navidrome: skipped (server not configured)");
            root._sourceDone(false);
            return;
        }

        navidromeStatus = status.searching;
        console.info("[PureLyrics] Navidrome: searching for \"" + expectedTitle + "\" by " + expectedArtist);

        var searchUrl = _navidromeUrl("search3", "query=" + encodeURIComponent(expectedTitle) + "&songCount=5&albumCount=0&artistCount=0");
        console.log("[PureLyrics] Navidrome: search URL = " + searchUrl);

        root._cancelActiveFetch = _xhrGet(searchUrl, 15000, function (responseText, httpStatus) {
            var rawData = (responseText || "").trim();
            console.log("[PureLyrics] Navidrome: search response length = " + rawData.length);
            if (rawData.length === 0) {
                root.navidromeStatus = status.error;
                console.warn("[PureLyrics] Navidrome: empty search response (HTTP " + httpStatus + ")");
                root._sourceDone(false);
                return;
            }
            try {
                var result = JSON.parse(rawData);
                var songs = result["subsonic-response"]?.searchResult3?.song;
                if (!songs || songs.length === 0) {
                    root.navidromeStatus = status.notFound;
                    console.info("[PureLyrics] ✗ Navidrome: no matching songs found for \"" + expectedTitle + "\"");
                    root._sourceDone(false);
                    return;
                }

                // Prefer exact title match, fall back to first result
                var songId = songs[0].id;
                for (var i = 0; i < songs.length; i++) {
                    if (songs[i].title.toLowerCase() === expectedTitle.toLowerCase()) {
                        songId = songs[i].id;
                        break;
                    }
                }

                console.log("[PureLyrics] Navidrome: song matched (id: " + songId + "), fetching lyrics…");
                root._fetchNavidromeLyrics(songId, expectedTitle, expectedArtist);
            } catch (e) {
                root.navidromeStatus = status.error;
                console.warn("[PureLyrics] Navidrome: failed to parse search response — " + e);
                console.warn("[PureLyrics] Navidrome: raw data: " + rawData.substring(0, 200));
                root._sourceDone(false);
            }
        }, function (errMsg) {
            root.navidromeStatus = status.error;
            console.warn("[PureLyrics] Navidrome: search request failed — " + errMsg);
            root._sourceDone(false);
        });
    }

    function _fetchNavidromeLyrics(songId, expectedTitle, expectedArtist) {
        var lyricsUrl = _navidromeUrl("getLyricsBySongId", "id=" + encodeURIComponent(songId));
        console.log("[PureLyrics] Navidrome: lyrics URL = " + lyricsUrl);

        root._cancelActiveFetch = _xhrGet(lyricsUrl, 15000, function (responseText, httpStatus) {
            var rawData = (responseText || "").trim();
            console.log("[PureLyrics] Navidrome: lyrics response length = " + rawData.length);
            if (rawData.length === 0) {
                root.navidromeStatus = status.error;
                console.warn("[PureLyrics] Navidrome: empty lyrics response (HTTP " + httpStatus + ")");
                root._sourceDone(false);
                return;
            }
            try {
                var result = JSON.parse(rawData);
                var lyricsList = result["subsonic-response"]?.lyricsList?.structuredLyrics;
                if (!lyricsList || lyricsList.length === 0) {
                    root.navidromeStatus = status.notFound;
                    console.info("[PureLyrics] ✗ Navidrome: no lyrics available for \"" + expectedTitle + "\"");
                    root._sourceDone(false);
                    return;
                }

                var synced = null;
                var unsynced = null;
                for (var i = 0; i < lyricsList.length; i++) {
                    if (lyricsList[i].synced) {
                        synced = lyricsList[i];
                        break;
                    } else {
                        unsynced = lyricsList[i];
                    }
                }

                if (synced && synced.line) {
                    var lines = synced.line.map(function (l) {
                        return {
                            time: (l.start || 0) / 1000,
                            text: l.value || ""
                        };
                    });
                    root.lyricsLines = lines;
                    root.navidromeStatus = status.found;
                    root.lyricStatus = lyricState.synced;
                    root.lyricSource = lyricSrc.navidrome;
                    console.info("[PureLyrics] ✓ Navidrome: synced lyrics found (" + lines.length + " lines) for \"" + expectedTitle + "\"");
                    if (root.cachingEnabled)
                        root.writeToCache(expectedTitle, expectedArtist, lines, lyricSrc.navidrome);
                    root._sourceDone(true);
                } else if (unsynced && unsynced.line) {
                    root.navidromeStatus = status.skippedPlain;
                    console.info("[PureLyrics] ✗ Navidrome: only plain lyrics found for \"" + expectedTitle + "\" (skipping, synced only)");
                    root._sourceDone(false);
                } else {
                    root.navidromeStatus = status.notFound;
                    console.info("[PureLyrics] ✗ Navidrome: lyrics structure empty for \"" + expectedTitle + "\"");
                    root._sourceDone(false);
                }
            } catch (e) {
                root.navidromeStatus = status.error;
                console.warn("[PureLyrics] Navidrome: failed to parse lyrics response — " + e);
                console.warn("[PureLyrics] Navidrome: raw data: " + rawData.substring(0, 200));
                root._sourceDone(false);
            }
        }, function (errMsg) {
            root.navidromeStatus = status.error;
            console.warn("[PureLyrics] Navidrome: lyrics request failed — " + errMsg);
            root._sourceDone(false);
        });
    }

    // -------------------------------------------------------------------------
    // lrclib.net fetch
    // -------------------------------------------------------------------------

    function _fetchFromLrclib(expectedTitle, expectedArtist) {
        lrclibStatus = status.searching;
        console.info("[PureLyrics] lrclib: searching for \"" + expectedTitle + "\" by " + expectedArtist);

        var url = "https://lrclib.net/api/get?artist_name=" + encodeURIComponent(expectedArtist) + "&track_name=" + encodeURIComponent(expectedTitle);
        if (currentAlbum)
            url += "&album_name=" + encodeURIComponent(currentAlbum);
        if (currentDuration > 0)
            url += "&duration=" + Math.round(currentDuration);

        root._cancelActiveFetch = _xhrGet(url, 20000, function (responseText, httpStatus) {
            var rawData = (responseText || "").trim();
            console.log("[PureLyrics] lrclib: response length = " + rawData.length);
            if (rawData.length === 0) {
                root.lrclibStatus = status.error;
                console.warn("[PureLyrics] lrclib: empty response (HTTP " + httpStatus + ")");
                root._sourceDone(false);
                return;
            }
            try {
                var result = JSON.parse(rawData);
                if (result.statusCode === 404 || result.error) {
                    root.lrclibStatus = status.notFound;
                    console.info("[PureLyrics] ✗ lrclib: no lyrics found for \"" + expectedTitle + "\"");
                    root._sourceDone(false);
                } else if (result.syncedLyrics) {
                    root.lyricsLines = root.parseLrc(result.syncedLyrics);
                    root.lrclibStatus = status.found;
                    root.lyricStatus = lyricState.synced;
                    root.lyricSource = lyricSrc.lrclib;
                    console.info("[PureLyrics] ✓ lrclib: synced lyrics found (" + root.lyricsLines.length + " lines) for \"" + expectedTitle + "\"");
                    if (root.cachingEnabled)
                        root.writeToCache(expectedTitle, expectedArtist, root.lyricsLines, lyricSrc.lrclib);
                    root._sourceDone(true);
                } else if (result.plainLyrics) {
                    root.lrclibStatus = status.skippedPlain;
                    console.info("[PureLyrics] ✗ lrclib: only plain lyrics found for \"" + expectedTitle + "\" (skipping, synced only)");
                    root._sourceDone(false);
                } else {
                    root.lrclibStatus = status.notFound;
                    console.info("[PureLyrics] ✗ lrclib: response contained no lyrics for \"" + expectedTitle + "\"");
                    root._sourceDone(false);
                }
            } catch (e) {
                root.lrclibStatus = status.error;
                console.warn("[PureLyrics] lrclib: failed to parse response — " + e);
                console.warn("[PureLyrics] lrclib: raw data: " + rawData.substring(0, 200));
                root._sourceDone(false);
            }
        }, function (errMsg) {
            root.lrclibStatus = status.error;
            console.warn("[PureLyrics] lrclib: request failed — " + errMsg);
            root._sourceDone(false);
        });
    }

    // -------------------------------------------------------------------------
    // api.lrc.cx fetch
    // -------------------------------------------------------------------------

    function _fetchFromLrcApi(expectedTitle, expectedArtist) {
        lrcapiStatus = status.searching;
        console.info("[PureLyrics] lrcapi: searching for \"" + expectedTitle + "\" by " + expectedArtist);

        var url = "https://api.lrc.cx/lyrics?artist=" + encodeURIComponent(expectedArtist) + "&title=" + encodeURIComponent(expectedTitle);
        if (currentAlbum)
            url += "&album=" + encodeURIComponent(currentAlbum);

        root._cancelActiveFetch = _xhrGet(url, 20000, function (responseText, httpStatus) {
            var rawData = (responseText || "").trim();
            console.log("[PureLyrics] lrcapi: response length = " + rawData.length);
            if (rawData.length === 0) {
                root.lrcapiStatus = status.error;
                console.warn("[PureLyrics] lrcapi: empty response (HTTP " + httpStatus + ")");
                root._sourceDone(false);
                return;
            }
            try {
                var lines = parseLrc(rawData);
                if (lines && lines.length > 0) {
                    root.lyricsLines = lines;
                    root.lyricStatus = lyricState.synced;
                    root.lrcapiStatus = status.found;
                    root.lyricSource = lyricSrc.lrcapi;
                    console.info("[PureLyrics] ✓ lrcapi: synced lyrics found (" + root.lyricsLines.length + " lines) for \"" + expectedTitle + "\"");
                    if (root.cachingEnabled)
                        root.writeToCache(expectedTitle, expectedArtist, root.lyricsLines, lyricSrc.lrcapi);
                    root._sourceDone(true);
                } else {
                    root.lrcapiStatus = status.notFound;
                    root._sourceDone(false);
                }
            } catch (e) {
                root.lrcapiStatus = status.error;
                console.warn("[PureLyrics] lrcapi: failed to parse response — " + e);
                console.warn("[PureLyrics] lrcapi: raw data: " + rawData.substring(0, 200));
                root._sourceDone(false);
            }
        }, function (errMsg) {
            root.lrcapiStatus = status.error;
            console.warn("[PureLyrics] lrcapi: request failed — " + errMsg);
            root._sourceDone(false);
        });
    }

    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Musixmatch fetch
    // -------------------------------------------------------------------------

    property string _musixmatchToken: pluginData.musixmatchToken ?? ""

    function _musixmatchHeaders() {
        return {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36",
            "Accept": "application/json",
            "Accept-Language": "en-US,en;q=0.9",
            "Origin": "https://www.musixmatch.com",
            "Referer": "https://www.musixmatch.com/"
        };
    }

    function _fetchMusixmatchToken(callback) {
        if (_musixmatchToken) {
            callback(_musixmatchToken);
            return;
        }

        var url = "https://apic-desktop.musixmatch.com/ws/1.1/token.get" + "?user_language=en" + "&app_id=web-desktop-app-v1.0" + "&t=" + Date.now();

        console.info("[PureLyrics] Musixmatch: fetching token…");

        root._cancelActiveFetch = _xhrGet(url, 15000, function (responseText, httpStatus) {
            try {
                var result = JSON.parse(responseText);
                var body = result.message ? result.message.body : undefined;
                var token = body ? body.user_token : undefined;
                if (token && token !== "undefined" && token !== "") {
                    root._musixmatchToken = token;
                    pluginService.savePluginData("pureLyrics", "musixmatchToken", token);
                    console.info("[PureLyrics] Musixmatch: token acquired");
                    callback(token);
                } else {
                    console.warn("[PureLyrics] Musixmatch: empty token in response");
                    callback(null);
                }
            } catch (e) {
                console.warn("[PureLyrics] Musixmatch: failed to parse token response — " + e);
                callback(null);
            }
        }, function (errMsg) {
            console.warn("[PureLyrics] Musixmatch: token request failed — " + errMsg);
            callback(null);
        }, _musixmatchHeaders());
    }

    function _fetchFromMusixmatch(expectedTitle, expectedArtist, _tokenRetried) {
        musixmatchStatus = status.searching;
        console.info("[PureLyrics] Musixmatch: searching for \"" + expectedTitle + "\" by " + expectedArtist);

        _fetchMusixmatchToken(function (token) {
            if (!token) {
                root.musixmatchStatus = status.error;
                console.warn("[PureLyrics] Musixmatch: no token available, cannot search");
                root._sourceDone(false);
                return;
            }

            // Guard: track may have changed
            if (expectedTitle !== root._lastFetchedTrack || expectedArtist !== root._lastFetchedArtist)
                return;

            var trackUrl = "https://apic-desktop.musixmatch.com/ws/1.1/matcher.track.get" + "?q_track=" + encodeURIComponent(expectedTitle) + "&q_artist=" + encodeURIComponent(expectedArtist) + "&page_size=1&page=1" + "&app_id=web-desktop-app-v1.0" + "&usertoken=" + encodeURIComponent(token) + "&t=" + Date.now();

            root._cancelActiveFetch = root._xhrGet(trackUrl, 15000, function (responseText, httpStatus) {
                try {
                    var result = JSON.parse(responseText);
                    var headerStatusCode = result.message && result.message.header ? result.message.header.status_code : 0;
                    if (headerStatusCode === 401 || headerStatusCode === 402) {
                        console.warn("[PureLyrics] Musixmatch: auth error (status_code=" + headerStatusCode + ") in matcher.track.get");
                        if (!_tokenRetried) {
                            root._musixmatchToken = "";
                            console.info("[PureLyrics] Musixmatch: token cleared, retrying with fresh token…");
                            root._fetchFromMusixmatch(expectedTitle, expectedArtist, true);
                        } else {
                            root.musixmatchStatus = status.error;
                            console.warn("[PureLyrics] Musixmatch: auth error persists after token refresh");
                            root._sourceDone(false);
                        }
                        return;
                    }
                    var track = result.message.body.track;
                    var trackId = track.track_id;
                    if (!trackId) {
                        root.musixmatchStatus = status.notFound;
                        console.info("[PureLyrics] ✗ Musixmatch: no track found for \"" + expectedTitle + "\"");
                        root._sourceDone(false);
                        return;
                    }

                    var hasSubtitles = track.has_subtitles === 1;
                    var hasLyrics = track.has_lyrics === 1;
                    console.info("[PureLyrics] Musixmatch: track matched (id: " + trackId + ", has_subtitles: " + hasSubtitles + ", has_lyrics: " + hasLyrics + ")");

                    if (!hasSubtitles) {
                        root.musixmatchStatus = hasLyrics ? status.skippedPlain : status.notFound;
                        console.info("[PureLyrics] ✗ Musixmatch: track has no synced lyrics (has_subtitles=0) for \"" + expectedTitle + "\"");
                        root._sourceDone(false);
                        return;
                    }

                    console.info("[PureLyrics] Musixmatch: fetching synced lyrics…");
                    root._fetchMusixmatchLyrics(trackId, token, expectedTitle, expectedArtist);
                } catch (e) {
                    root.musixmatchStatus = status.error;
                    console.warn("[PureLyrics] Musixmatch: failed to parse track response — " + e);
                    root._sourceDone(false);
                }
            }, function (errMsg) {
                root.musixmatchStatus = status.error;
                console.warn("[PureLyrics] Musixmatch: track request failed — " + errMsg);
                root._sourceDone(false);
            }, _musixmatchHeaders());
        });
    }

    function _fetchMusixmatchLyrics(trackId, token, expectedTitle, expectedArtist, _tokenRetried) {
        var url = "https://apic-desktop.musixmatch.com/ws/1.1/track.subtitle.get" + "?track_id=" + trackId + "&subtitle_format=lrc" + "&app_id=web-desktop-app-v1.0" + "&usertoken=" + encodeURIComponent(token) + "&t=" + Date.now();

        root._cancelActiveFetch = _xhrGet(url, 15000, function (responseText, httpStatus) {
            // Guard: track may have changed
            if (expectedTitle !== root._lastFetchedTrack || expectedArtist !== root._lastFetchedArtist)
                return;

            try {
                var result = JSON.parse(responseText);
                var headerStatusCode = result.message && result.message.header ? result.message.header.status_code : 0;
                if (headerStatusCode === 401 || headerStatusCode === 402) {
                    console.warn("[PureLyrics] Musixmatch: auth error (status_code=" + headerStatusCode + ") in track.subtitle.get");
                    if (!_tokenRetried) {
                        root._musixmatchToken = "";
                        console.info("[PureLyrics] Musixmatch: token cleared, retrying with fresh token…");
                        root._fetchFromMusixmatch(expectedTitle, expectedArtist, true);
                    } else {
                        root.musixmatchStatus = status.error;
                        console.warn("[PureLyrics] Musixmatch: auth error persists after token refresh");
                        root._sourceDone(false);
                    }
                    return;
                }
                var subtitleBody = result.message.body.subtitle.subtitle_body;
                if (!subtitleBody || subtitleBody.trim() === "") {
                    root.musixmatchStatus = status.notFound;
                    console.info("[PureLyrics] ✗ Musixmatch: no synced lyrics for \"" + expectedTitle + "\"");
                    root._sourceDone(false);
                    return;
                }

                var lines = root.parseLrc(subtitleBody);
                if (lines.length === 0) {
                    root.musixmatchStatus = status.notFound;
                    console.info("[PureLyrics] ✗ Musixmatch: failed to parse LRC for \"" + expectedTitle + "\"");
                    root._sourceDone(false);
                    return;
                }

                root.lyricsLines = lines;
                root.musixmatchStatus = status.found;
                root.lyricStatus = lyricState.synced;
                root.lyricSource = lyricSrc.musixmatch;
                console.info("[PureLyrics] ✓ Musixmatch: synced lyrics found (" + lines.length + " lines) for \"" + expectedTitle + "\"");
                if (root.cachingEnabled)
                    root.writeToCache(expectedTitle, expectedArtist, lines, lyricSrc.musixmatch);
                root._sourceDone(true);
            } catch (e) {
                root.musixmatchStatus = status.error;
                console.warn("[PureLyrics] Musixmatch: failed to parse lyrics response — " + e);
                root._sourceDone(false);
            }
        }, function (errMsg) {
            root.musixmatchStatus = status.error;
            console.warn("[PureLyrics] Musixmatch: lyrics request failed — " + errMsg);
            root._sourceDone(false);
        }, _musixmatchHeaders());
    }

    // -------------------------------------------------------------------------
    // LRC parser
    // -------------------------------------------------------------------------

    function parseLrc(lrcText) {
        var timeRegex = /\[(\d{2}):(\d{2})\.(\d{2,3})\]/;
        // Metadata lines (lyricist/composer/arranger/producer etc.) to drop
        var metaRegex = /^(作词|作曲|编曲|制作人|制作|录音|混音|混缩|母带|母带处理|监制|企划|统筹|文案|发行|唱片公司|和声|和音|配唱|吉他|贝斯|鼓|键盘|弦乐|制作发行|出品|词|曲|Lyrics?|Composer|Arranger|Producer|Produced|Recorded|Mixed|Mastering|Mastered|Vocals?|Guitar|Bass|Drums|Keyboard|Engineer|Mix|Backing Vocal|Background Vocal)[:：\s]/i;
        var result = lrcText.split("\n").reduce(function (acc, rawLine) {
            var line = rawLine.trim();
            if (!line)
                return acc;
            var match = timeRegex.exec(line);
            if (!match)
                return acc;
            var text = line.replace(/\[\d{2}:\d{2}\.\d{2,3}\]/g, "").trim();
            // Drop metadata lines so the first visible line is actual lyrics
            if (metaRegex.test(text))
                return acc;
            var millis = parseInt(match[3]);
            if (match[3].length === 2)
                millis *= 10;
            acc.push({
                time: parseInt(match[1]) * 60 + parseInt(match[2]) + millis / 1000,
                text: text
            });
            return acc;
        }, []);
        result.sort(function (a, b) {
            return a.time - b.time;
        });
        return result;
    }

    // -------------------------------------------------------------------------
    // Position tracking for synced lyrics
    // -------------------------------------------------------------------------

    // Lyrics timestamps are sorted ascending; binary search keeps the
    // 100ms poll cheap even for long tracks (O(log n) instead of O(n)).
    function findLineIndex(pos) {
        var lines = root.lyricsLines;
        var lo = 0, hi = lines.length - 1, result = -1;
        while (lo <= hi) {
            var mid = (lo + hi) >> 1;
            if (pos >= lines[mid].time) {
                result = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return result;
    }

    Timer {
        id: positionTimer
        interval: 100
        running: root.lyricPlayer && lyricsLines.length > 0
        repeat: true
        onTriggered: {
            root._releaseLockIfStopped();
            var lp = root.lyricPlayer;
            if (!lp)
                return;
            var rawPos = lp.position || 0;
            var pos = rawPos + root.scrollOffset / 1000.0;
            var newIndex = root.findLineIndex(pos);
            if (newIndex !== currentLineIndex)
                currentLineIndex = newIndex;
        }
    }

    // -------------------------------------------------------------------------
    // Status chip helpers
    // -------------------------------------------------------------------------

    readonly property var _chipMeta: ({
            [status.searching]: {
                color: Theme.secondary,
                icon: "hourglass_top",
                label: "Searching…"
            },
            [status.found]: {
                color: Theme.primary,
                icon: "check_circle",
                label: "Found: Synced lyrics"
            },
            [status.notFound]: {
                color: Theme.warning,
                icon: "cancel",
                label: "Not found"
            },
            [status.error]: {
                color: Theme.error,
                icon: "error",
                label: "Error"
            },
            [status.skippedConfig]: {
                color: Theme.warning,
                icon: "block",
                label: "Skipped: Not configured"
            },
            [status.skippedFound]: {
                color: Theme.warning,
                icon: "block",
                label: "Skipped: Already found"
            },
            [status.skippedPlain]: {
                color: Theme.warning,
                icon: "block",
                label: "Skipped: Plain lyrics"
            },
            [status.cacheHit]: {
                color: Theme.primary,
                icon: "check_circle",
                label: "Hit: Loaded from cache"
            },
            [status.cacheMiss]: {
                color: Theme.warning,
                icon: "cancel",
                label: "Miss: Not in cache"
            },
            [status.cacheDisabled]: {
                color: Theme.surfaceVariantText,
                icon: "do_not_disturb_on",
                label: "Disabled"
            }
        })

    function _chip(val) {
        return _chipMeta[val] ?? {
            color: Theme.surfaceContainerHighest,
            icon: "radio_button_unchecked",
            label: "Idle"
        };
    }

    function chipColor(val) {
        return _chip(val).color;
    }
    function chipIcon(val) {
        return _chip(val).icon;
    }
    function chipLabel(val) {
        return _chip(val).label;
    }

    // -------------------------------------------------------------------------
    // Bar Pills: show current lyric line
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------
    // Desktop rendering: synced lyrics (ListView, centered follow)
    // -------------------------------------------------------------------------

    implicitWidth: 600
    implicitHeight: root.fontSize * root.lineCount * 1.4 + 8
    minWidth: 120
    minHeight: 40

    // Hide entirely when no active media is playing (fade out)
    readonly property bool hasActiveMedia: {
        const lp = root.lyricPlayer;
        return !!lp && lp.playbackState !== MprisPlaybackState.Stopped;
    }
    opacity: root.hasActiveMedia ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    // Loading / idle / not-found status text
    StyledText {
        anchors.centerIn: parent
        width: parent.width * 0.9
        horizontalAlignment: Text.AlignHCenter
        text: {
            if (root.lyricsLoading) return I18n.tr("Searching lyrics…")
            if (root.lyricStatus === lyricState.notFound) return I18n.tr("No synced lyrics found")
            if (root.currentTitle) return root.currentTitle
            return I18n.tr("No lyrics")
        }
        font.pixelSize: root.fontSize
        color: Theme.surfaceVariantText
        elide: Text.ElideRight
        visible: root.lyricsLines.length === 0
    }

    // Background card (optional, behind lyrics)
    Rectangle {
        anchors.fill: parent
        radius: 16
        color: root.backgroundOpacity > 0 ? Theme.withAlpha(Theme.surfaceContainerHighest, root.backgroundOpacity) : "transparent"
        border.color: root.borderOpacity > 0 ? Theme.withAlpha(Theme.outline, root.borderOpacity) : "transparent"
        border.width: root.borderOpacity > 0 ? 1 : 0
        visible: root.backgroundOpacity > 0 || root.borderOpacity > 0
    }

    ListView {
        id: lyricsListView
        anchors.fill: parent
        visible: root.lyricsLines.length > 0
        clip: true
        model: root.lyricsLines
        currentIndex: root.currentLineIndex >= 0 ? root.currentLineIndex : 0
        highlightFollowsCurrentItem: true
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: height * 0.50 - root.fontSize * 0.70
        preferredHighlightEnd: height * 0.50 + root.fontSize * 0.70
        cacheBuffer: root.lineCount * 2
        spacing: root.fontSize * 0.15

        // Spacer half on top and bottom so the first and last line can scroll to center (fixes lyrics-start top-aligned bug)
        header: Item {
            width: 1
            height: Math.max(0, (lyricsListView.height - root.fontSize * 1.4) / 2)
        }
        footer: Item {
            width: 1
            height: Math.max(0, (lyricsListView.height - root.fontSize * 1.4) / 2)
        }

        Behavior on contentY {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            required property int index
            required property var modelData
            width: lyricsListView.width
            readonly property bool isEmptyLine: !modelData || !modelData.text || modelData.text.trim() === ""
            height: root.fontSize * 1.4

            readonly property int dist: Math.abs(index - lyricsListView.currentIndex)
            readonly property int maxDist: Math.floor(root.lineCount / 2)

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                horizontalAlignment: {
                    if (root.textAlign === "left") return Text.AlignLeft;
                    if (root.textAlign === "right") return Text.AlignRight;
                    return Text.AlignHCenter;
                }
                elide: Text.ElideRight
                maximumLineCount: 1
                // Empty line (paragraph break) shows ♪ placeholder, consistent with materialPlayer
                text: modelData ? (modelData.text || "♪") : "♪"

                // Font size: current line = fontSize, shrinking with distance
                font.pixelSize: {
                    if (dist === 0) return root.fontSize;
                    if (dist === 1) return root.fontSize * 0.82;
                    if (dist === 2) return root.fontSize * 0.68;
                    return root.fontSize * 0.56;
                }
                font.weight: dist === 0 ? Font.DemiBold : Font.Normal
                // Lines beyond the lineCount range are hidden; empty lines always dimmed
                opacity: parent.dist > parent.maxDist ? 0 : (parent.isEmptyLine ? 0.25 : (dist === 0 ? 1.0 : dist === 1 ? 0.6 : dist === 2 ? 0.35 : 0.18))
                color: dist === 0 ? root.accentColor : Theme.surfaceText

                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on font.pixelSize { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        }
    }

    Component.onCompleted: {
        console.info("[PureLyrics] Desktop widget loaded");
    }
}
