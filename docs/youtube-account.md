# Experimental YouTube account support (Android)

In Online Music, select YouTube Music, then YouTube account > Sign in.
Complete sign-in on Google's page. Once YouTube Music has loaded, tap Use
account. The app reports Session saved, not verified playback. Select a track
again to attempt playback. YouTube account > Sign out removes the local session.
Signing into the external YouTube app alone does not connect RetroPod.

Google may reject embedded browser sign-in. RetroPod does not disguise the
WebView as another browser or override certificate failures. In that case this
sign-in method is unavailable; use the external YouTube Music app. Do not send
passwords or cookies in chat, logs, issues or screenshots.

## Scope and limitations

Only the built-in YouTube Music provider uses this session. Piped and Mornye
extensions never receive it. Search remains public. Authenticated playback uses
the signed-in WEB_REMIX client configuration and a scoped request to YouTube's
player endpoint. Only direct HTTPS Googlevideo audio URLs are returned to the
existing player. Signature-cipher and proof-of-origin token handling are not
implemented; sign-in therefore does not guarantee playable audio.

YT_SESSION_EXPIRED means reconnect the account. YT_SESSION_REJECTED means the
request was denied. YT_SESSION_NO_AUDIO means no supported direct audio URL was
returned. A failed authenticated request may still use the existing anonymous
Piped fallback, without credentials.

## Session handling

Passwords are entered only into Google's page. No JavaScript bridge is exposed.
Navigation is limited to named HTTPS Google/YouTube hosts, including the
YouTube account handoff and Google India sign-in hosts; session configuration
is read only on the exact YouTube Music origin. Session cookies remain native.
The saved session is AES-GCM encrypted using Android Keystore and stored under
noBackupFilesDir. WebView storage/cookies are cleared after the sign-in dialog
closes; WebView data is excluded from backup and device-transfer rules. Closing
the app abruptly during sign-in can leave temporary WebView state until the
next sign-in clears it. Signed-out audio already buffered by the player may
continue; sign-out removes future authenticated access, not the Google account.

## Validation

Unit tests cover session lifecycle channel operations, credential-free resolver
arguments, signed-in resolver selection, safe errors and stream-host validation.
An APK compile and device testing are still required for the WebView interaction
and real authenticated playback; mocked tests do not prove either works.

Sign-in recovery now includes Start over, page/certificate errors, a 30-second
slow-page notice and a 10-second timeout for reading the account configuration.
First-party session cookies are recognized. These changes address silent
redirect rejection and indefinite account-check UI; they do not bypass Google
verification or establish that every device can sign in.
