# Custom Lastwave-format HTTP add-on

Online Music > Custom add-on opens configuration. Open setup website launches
https://lastwaveaddons.clashprojects.qd.je in the device browser. That site is an
account dashboard; create/verify your own account there and copy the personal
add-on URL. Paste it into the obscured field, Check and save, then Use this add-on.
The homepage alone is deliberately rejected. No shared provider token is bundled.

RetroPod checks GET /manifest.json before saving a private endpoint in Android
Keystore-encrypted, non-backup storage. Search uses /search?q=...&quality=lossless
&atmos=none. Selecting a result resolves /stream/{id} afresh, accepting direct
HTTPS audio URLs. Stable track references contain only a local configuration ID
and provider track ID. Replacing/removing an endpoint invalidates its old results.
Remove saved add-on deletes the private configuration. Google sessions are never
attached to add-on requests. HTTP redirects are not followed, to avoid forwarding
a token-bearing endpoint to another location; errors never include raw bodies.

This is independently implemented protocol compatibility, not a copy of Lastwave
or Podium. Reference: Clash-Projects/LastWave-Native data/addon/AddonClient.kt and
AddonModels.kt. No private app-signing secret, encrypted .lwp runtime, hybrid
stream decryption, custom playback headers or license handling is included.
A server requiring any of these may reject RetroPod or return unsupported audio.
A manifest check is not a claim of playable audio or provider authorization.

Validation uses mock manifest/search/stream responses and Android policy tests.
Live playback on this account-gated service is unverified until a user configures
their own endpoint and tests it on device. Never put private URLs in repository
issues, logs, screenshots or chat.
