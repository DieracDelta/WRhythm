WRhythm's another streaming app for open subsonic API implementors like Navidrome on apple devices.

But there's a lot of these. Why WRhythm?

A few reasons:

- Multiparty suite
  - Problem: There's no multi-client suite of apps as far as I know. Solution: WRhythm is on iPhone, MacOS, and WatchOS
  - Problem: Imagine I'm streaming a song on my mac, but then I want to go on a walk. Solution: With WRhythm you can just say "Play on my Iphone" and it plays on your iphone.
  - Problem: Imagine I'm in bed and want to skip a song playing on my mac. Soluiton: I can do that from my Iphone or apple watch with WRhythm.
- WatchOS
  - Problem: There's no watchos client.
  - Solution: WRhythm provides a standalone watchos client saving you from having to bring your phone to stream music.
- Offline First:
  - Problem: Typically if you lose reception, you won't be able to play music very easily unless you thought ahead and downloaded music.
  - Solution: WRhythm saves the past `n` where `n` is configurable songs. And WRhythm buffers the next `m` songs where `m` is configurable. So hopefully you never end up without music.
- Playlist gen is difficult and not great compared to spotify
  - Problem: building playlists is annoying and not very easy to do
  - WRhythm supports [this extension](https://opensubsonic.netlify.app/docs/extensions/sonicsimilarity/)
  - WRhythm supports [audiomuse-ai-server](https://github.com/NeptuneHub/AudioMuse-AI-MusicServer/issues) specific endpoints
