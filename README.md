# Pure Lyrics

A minimal, floating desktop widget that displays **real-time synced lyrics**. No player UI, no visualizer, no bloat — just lyrics, highly customizable.

## Features

- **Synced lyrics** from multiple sources with automatic fallback:
  1. Local cache (fast, offline)
  2. LRCLIB
  3. LRC API (`api.lrc.cx`)
  4. Musixmatch
  5. Navidrome (optional, self-hosted)
- **Always-centered scrolling** — the current line stays vertically centered as it scrolls (no "stuck at top" bug)
- **Three-tier emphasis** — current line is large/bright, context lines shrink and fade with distance
- **Empty-line handling** — paragraph breaks show a subtle `♪` placeholder (consistent with Material Player & Lyrics)
- **Metadata filtering** — drops `作词/作曲/编曲` / `Lyrics/Composer/Producer` header lines from lyrics
- **MPRIS player selection** — preferred player (auto/spotify/firefox/chromium/mpv/vlc/termusic) + duplicate instance filtering
- **Sync offset** — adjust lyric timing from -3s to +3s
- **No media fade** — widget gently fades out when nothing is playing

## Customization

Configured in **DMS Settings → Desktop Widgets → Pure Lyrics**:

- Font size (12–64px)
- Lines shown (1/3/5/7)
- Text alignment (left/center/right)
- Sync offset (±3s)
- Accent color (system primary / secondary / custom hex)
- Background card opacity + border opacity
- Source priority (cache → LRCLIB → LRC API → Musixmatch → Navidrome)
- Cache toggle
- Navidrome server credentials
- Preferred player + duplicate filtering

## Installation

1. Clone into your DMS plugins directory:

   ```bash
   git clone https://github.com/lildengzi/pureLyrics ~/.config/DankMaterialShell/plugins/pureLyrics
   ```

2. Open **DMS Settings → Plugins**, click **Scan**, and toggle **Pure Lyrics** on.
3. Add the widget to your desktop via **Desktop Widgets**.
4. Play some music and enjoy.

## Requirements

- DMS >= 1.2.0
- An MPRIS-capable media player (Spotify, termusic, mpv, browsers, etc.)

## Notes

- The widget is pure display — click-through is available via the desktop widget settings.
- Lyrics sources are public, non-commercial APIs used at low request rates for personal use.
