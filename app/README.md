# Dialbase Flutter Demo

A native audio-call client for the Laravel Dialbase demo backend. The app demonstrates authentication, user discovery, shared web/mobile presence, incoming calls, WebRTC audio and local call history.

## Run

```sh
flutter pub get
flutter run --dart-define=DIALBASE_API_URL=https://dialbase.test/api/v1
```

For a reusable configuration, copy `config/development.example.json` to
`config/development.json`, set your backend URL, and run:

```sh
flutter run --dart-define-from-file=config/development.json
```

This config contains only the demo backend URL. Do not add Dialbase product
credentials to the app: secrets compiled into an APK are not private.

## Android APK for Two-User Testing

Deploy the Laravel backend and Reverb to reachable HTTPS/WSS hosts first. From
this directory, build a test APK with your own public backend URL:

```sh
flutter build apk --release --dart-define=DIALBASE_API_URL=https://your-demo-backend.example.com/api/v1
```

The APK is generated at `build/app/outputs/flutter-apk/app-release.apk`. This
demo uses debug signing for sideload testing, not Play Store publishing. A fresh
checkout needs a configured Android SDK/JDK; Flutter recreates its generated
platform files. Never commit APKs, keystores or `key.properties`.

Install on two phones, register two different accounts on the same backend,
verify both emails, keep both apps open and allow microphone access. Call, answer,
speak in both directions, test mute/speaker/end and tap a recent call to redial.
One phone and the web dashboard can also test together. Reverb's advertised WSS
host must be reachable by both devices, not just by the Laravel server.

For iPhone device builds, choose your own signing team and Bundle ID in Xcode.
No personal Apple signing team or certificates are included in this source.

The default API is the local Herd backend, not the Dialbase management dashboard. For a physical phone, set `DIALBASE_API_URL` to your backend's reachable HTTPS address. `.test` domains and Mac loopback addresses are not reachable from a separate phone by default. Do not disable TLS verification; trust the local Herd CA in the simulator or use a publicly trusted HTTPS server.

Configure the Laravel backend's Dialbase credentials and start Reverb. `GET /calls/config` supplies the public Reverb host, port and app key; the returned host must also be reachable by the phone. Credentials and product secrets belong only in the backend environment.

Register or sign in with a demo backend account. Verify its email using the existing web verification flow, then sign in to the app. Test with two different users, either on two devices or one device and the web demo. Accounts with two-factor authentication currently need the web sign-in flow.

## Calling Flow

1. Login returns an app Bearer token, stored in platform secure storage.
2. `/users` loads verified peers; Reverb `presence-calls` supplies live availability shared with the web demo.
3. `/calls/session` supplies a separate Dialbase JWT, WebSocket URL and ICE servers.
4. The signaling socket authenticates with `jwt` and the session token as subprotocols, then waits for `auth.ok`.
5. Invite/accept/cancel/end events use Dialbase; WebRTC carries microphone audio.
6. Speaker and mute controls operate on native audio. The duration starts when WebRTC connects, not when the invitation is sent.
7. `/calls/history` records each user's demo call history. These client-reported records are not authoritative billing records.

Session tokens refresh before expiry, and the socket reconnects after a disconnect. Outgoing cancellation waits for the invite UUID when necessary. Stale events cannot end a different active call. Microphone tracks, timers, sockets and audio playback are released when leaving the signed-in app.

Calls are supported while the app is running in the foreground. This demo does not yet implement APNs/FCM incoming-call push, CallKit or Android ConnectionService. Do not rely on it to receive calls when the OS suspends or closes the app.

## Code Map

- `lib/core/network/dialbase_api.dart`: JSON requests and Bearer authorization.
- `lib/features/auth/data`: API authentication and secure token storage.
- `lib/features/calling/data/call_signaling.dart`: Dialbase session/socket lifecycle.
- `lib/features/calling/data/call_presence.dart`: Reverb presence and Echo-compatible availability whispers.
- `lib/features/calling/data/call_controller.dart`: call lifecycle, microphone/audio routing and history.
- `lib/features/calling/presentation/screens/call_screen.dart`: incoming and connected call UI.

The ringtone is bundled, with its reproducible generator in `tool/generate_ringtone.dart`.

## Sharing the Source

Source and lockfiles are included; secure-storage tokens, SQLite databases,
local configuration, SDK paths, build output and signing files are not. The
test accounts are isolated fixtures, not exported real users. The backend's
SQLite file is never part of the app or source release. Account registration
and history remain Laravel responsibilities; Reverb only supplies presence,
and Dialbase supplies calling infrastructure.

## Checks

```sh
flutter analyze
flutter test
flutter build ios --simulator --debug
```

Connection tests use local mock WebSockets and never make paid Dialbase calls. Widget tests cover the call controls, small screens and larger text. Regenerate the call screenshot with `flutter test test/features/calling/call_screen_test.dart --update-goldens` after intentional layout changes.
