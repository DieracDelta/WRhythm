# AudioMuse-AI Feature Port Plan

## Goal

Port AudioMuse-AI MusicServer features into WRhythm without making them part of the default Subsonic/Navidrome experience. Anything that depends on AudioMuse private `/api/...` routes stays hidden behind the existing `experimentalAudioMuseFeaturesEnabled` setting.

## Architecture

- Keep standard Subsonic behavior in `NavidromeAPI` as the default path.
- Add a small AudioMuse capability layer in `NavidromeAPI` that probes concrete private endpoints with short timeouts and caches support in `UserDefaults`.
- Keep UI modes disabled unless both conditions are true:
  - `experimentalAudioMuseFeaturesEnabled == true`
  - the specific AudioMuse endpoint probe reports available
- Route all generated playlists through `AudioPlayer.startPlaylistGeneration(...)` so queue restoration, cancellation, warnings, and playback pause/resume semantics stay consistent.
- Prefer plain Swift policy types for mode visibility, response decoding, and paging so behavior is covered by unit tests before UI is wired.

## 1. CLAP / Vibe Search

- Probe: `GET /api/clap/top_queries`
- Search: `POST /api/clap/search`
- UI:
  - Add an AudioMuse search mode in Search when experimental features are enabled and CLAP is available.
  - Show top-query chips when available.
  - Return hydrated `Song` rows only.
- Tests:
  - Decode CLAP response into songs.
  - Confirm endpoint status policy treats `200` and authenticated-but-empty responses as available.
  - Confirm CLAP mode is hidden when experimental features are off.

## 2. Semantic Text Search

- Probe: `POST /api/semantic-search` with a tiny harmless query and short timeout.
- Search: `POST /api/semantic-search`
- UI:
  - Add a semantic text search mode beside library and CLAP search.
  - Return hydrated `Song` rows only.
- Tests:
  - Decode semantic response into songs.
  - Confirm semantic mode is hidden without the experimental setting.

## 3. AI Radio Stations

- Endpoints:
  - `POST /api/radios`
  - `GET /api/radios`
  - `GET /api/radios/:id/seed`
  - `PUT /api/radios/:id/name`
  - `DELETE /api/radios/:id`
- UI:
  - Add a Playlist Gen section for persistent AudioMuse radio stations.
  - Saving a station stores seed songs plus temperature/subtract distance.
  - Starting a station fetches the seed and runs Alchemy through the existing playlist generation flow.
- Tests:
  - Decode radio station list/seed payloads.
  - Encode create-radio payloads deterministically.
  - Verify stations are hidden unless experimental AudioMuse features are enabled.

## 4. Private Sonic Wrappers

- AudioMuse-MusicServer exposes nonstandard wrappers:
  - `/rest/getSimilarSongs`
  - `/rest/getSongPath`
  - `/rest/getSonicFingerprint`
- WRhythm already has official OpenSubsonic-style UI for sonic similarity. Add fallback compatibility methods for AudioMuse private names instead of assuming `getSonicSimilarTracks` / `findSonicPath` exist everywhere.
- UI:
  - Prefer official OpenSubsonic `sonicSimilarity` if advertised.
  - When experimental AudioMuse features are enabled, probe and use AudioMuse private wrappers as fallback generator modes.
- Tests:
  - Decode private directory-style responses.
  - Confirm fallback endpoint selection order.

## 5. Similar Artists

- Endpoint: `/rest/getSimilarArtists2`
- UI:
  - Add a compact “Similar Artists” section on artist detail pages when available.
  - Tapping an artist opens `ArtistDetailView`.
  - Add action to generate a playlist from similar artists later if the API is reliable.
- Tests:
  - Decode `similarArtists2.artist`.
  - Confirm unavailable/empty results do not break artist detail rendering.

## 6. Music Map / Voyager

- Endpoints:
  - `GET /api/map`
  - `GET /api/voyager/search_tracks`
  - `POST /api/map/create_playlist`
- UI:
  - Start macOS/iPad only.
  - First slice should expose “Create playlist from map selection” before building a full custom map renderer.
  - Avoid watchOS for map visualization.
- Tests:
  - Decode map track search/autocomplete results.
  - Verify create-playlist request payload.
  - Confirm map UI remains hidden on watchOS and when experimental features are disabled.

## Rollout Order

1. Capability models, probes, response decoding tests.
2. CLAP and semantic search in `TracksView`.
3. AudioMuse private sonic wrapper fallback in Playlist Gen.
4. Similar artists on artist detail.
5. AI Radio station list and start flow.
6. Music map/voyager macOS/iPad surface.

## Non-goals

- Do not expose AudioMuse private routes when the experimental feature setting is off.
- Do not make AudioMuse routes prerequisites for normal playback, downloads, favorites, scrobbling, or Subsonic search.
- Do not add heavy map UI to watchOS.
