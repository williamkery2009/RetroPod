# Custom Lastwave-format HTTP add-on

Online Music > Custom add-on opens configuration. Open setup website launches
https://lastwaveaddons.clashprojects.qd.je in the device browser. That site is an
account dashboard; create/verify your own account there and copy the personal
add-on URL. Paste it into the obscured field, Check and save, then Use this add-on.
The homepage alone is deliberately rejected. No shared provider token is bundled.

RetroPod checks GET /manifest.json before saving a private endpoint in Android
Keystore-encrypted, non-backup storage. Search uses /search?q=... plus the manifest-declared setting defaults. The same
settings go to /stream/{id}; quality and atmos are no longer forced. Existing
configurations fetch their manifest defaults automatically. Re-saving stores
the defaults with the encrypted endpoint. Manifest settings that list options
(such as quality) can be changed on the add-on screen. Changing one keeps the
configuration ID, so existing results stay valid. Query tokens in endpoint URLs are preserved. Selecting a result resolves /stream/{id} afresh, accepting direct
HTTPS audio URLs, including relative paths resolved against the add-on base.
DASH/HLS hints select the matching player source. Validated provider playback
headers are kept in memory only and passed to the native player; they are not
written to track metadata. Stable track references contain only a local configuration ID
and provider track ID. Replacing/removing an endpoint invalidates its old results.
Remove saved add-on deletes the private configuration. Google sessions are never
attached to add-on requests. HTTP redirects are not followed, to avoid forwarding
a token-bearing endpoint to another location; errors never include raw bodies.

This is independently implemented protocol compatibility, not a copy of Lastwave
or Podium. Reference: Clash-Projects/LastWave-Native data/addon/AddonClient.kt and
AddonModels.kt. No private app-signing secret, encrypted .lwp runtime, hybrid
stream decryption, license handling is included.
A server requiring any of these may reject RetroPod or return unsupported audio.
A manifest check is not a claim of playable audio or provider authorization.

Validation uses mock manifest/search/stream responses and Android policy tests.
Live playback on this account-gated service is unverified until a user configures
their own endpoint and tests it on device. Never put private URLs in repository
issues, logs, screenshots or chat.

Compatibility follow-up references Podium sources/addon at commit
93a8845f02e9284a7e308cb7f791868fd52caec7: manifest defaults, exact provider IDs,
relative media paths, playback headers and container hints. This is an independent
Dart implementation, not a port of Podium's Kotlin code or full provider resolver.
No cross-catalogue fuzzy matching, retry hedging or DRM support is added.
The server remains responsible for returning audio for the requested track ID.
These compatibility fixes do not establish that the reported wrong recording is
fixed: live requests from the development environment return HTTP 403.

Probes on 2026-11-28 of one LastWave Addons account: manifest and search worked,
but stream responses for two tracks pointed to files in a "pranks-cdn" GitHub
repository on jsDelivr, labelled as FLAC. RetroPod rejects these (ADDON_DECOY).
The check covers only that observed source and does not verify that other audio
matches the requested track. The reason the provider sends them is unknown.
