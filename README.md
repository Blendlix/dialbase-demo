# Dialbase Demo

Learn how to connect web and native clients to Dialbase audio calls.

This repository contains two clients of the same demo backend:

- [`backend/`](backend/README.md): Laravel API, registration, Reverb presence and the web dashboard.
- [`app/`](app/README.md): Flutter native app, audio-call screen and recent-call redial.

## Start Here

1. Follow the backend README to install dependencies and configure your own Dialbase credentials.
2. Start Laravel and Reverb; register and verify two different demo accounts.
3. Test two browser profiles, or configure the Flutter app with this backend's `/api/v1` URL.
4. Allow microphones, call the other account and answer the incoming call.

For remote Android testing, deploy the backend and Reverb with public HTTPS/WSS
addresses, then use the APK build command in the app README. Keep both clients
open: background incoming-call push and CallKit are outside this demo's scope.

## Architecture

Laravel owns accounts, API authentication, the directory and demo history.
Reverb supplies online/ready/busy presence. Dialbase supplies session authorization,
call events, signaling and STUN/TURN servers. WebRTC carries the microphone audio.
Product secrets belong only on the backend, never in Flutter or browser assets.

Read [`backend/CALLING.md`](backend/CALLING.md) for the flow and code entrypoints,
and [`backend/API.md`](backend/API.md) for the mobile API. Incoming UI, ringtone,
mute, call duration, minimize and history are included. History is demo data,
not an authoritative billing record.

## Privacy Before Publishing

This source snapshot excludes live databases, users, tokens, logs, uploads,
archives, signing files and local environment files. Each installation creates
its own SQLite database and accounts. Tests use fictional fixtures.

Before the first push, stage the intended source and run:

```sh
node tools/check-release.mjs
```

With a Git repository present, the check scans tracked/staged files. Without one,
it scans the source snapshot. Ignore rules do not remove previously committed
secrets or database files from Git history. Review staged files and history before
pushing, and rotate any secret that has already been exposed. The check is an
additional guard, not a guarantee against every kind of private information.

## License

MIT. See [LICENSE](LICENSE). Third-party dependencies retain their own licenses.
Bundled MP3 recordings need their own redistribution rights; the code license
does not grant rights to audio from another creator.
