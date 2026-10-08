# Dialbase Demo Backend

A working reference for integrating Dialbase audio calls into Laravel and Flutter apps. It includes registration, online users, incoming-call UI, ringtones, mute, duration and per-user call history.

## What Runs Where

| Component | Responsibility |
| --- | --- |
| Laravel + Fortify/Sanctum | Accounts, email verification, API tokens, users and demo history |
| Laravel Reverb | Presence and ready/busy availability |
| Dialbase | Calling sessions, call-state events, signaling and STUN/TURN credentials |
| WebRTC | Microphone audio between the connected clients |

The demo backend is not a replacement for Dialbase's calling infrastructure. Product credentials stay in Laravel; browsers and phones receive temporary session tokens.

## Install

For an explicit clone-to-first-call walkthrough, including full `.env` settings,
individual install commands, verification and Flutter setup, start with the
[root README](../README.md). The shortcut below is for fresh installations.

Requirements: PHP 8.3+, Composer, SQLite support, Node.js 22.12+ with npm. The mobile client additionally needs a compatible Flutter SDK.

From this directory:

```sh
composer setup
```

This installs dependencies, copies `.env.example` only if `.env` is absent, generates an app key, creates an empty SQLite file only if needed, migrates tables and builds frontend assets. It does not seed demo accounts or copy an existing database. Do not run `migrate:fresh` on a database you want to preserve.

`composer setup` is for a fresh checkout: it generates a new app key. Do not
use it to update an existing installation with encrypted data; run dependency
installation, migrations and asset builds individually instead.

Edit `.env` with your own Dialbase product key ID and secret:

```dotenv
BLENDLIX_CALL_BASE_URL=https://rtc-svc.blendlix.com
BLENDLIX_CALL_PRODUCT_KEY_ID=your-product-key-id
BLENDLIX_CALL_PRODUCT_SECRET=your-product-secret
BLENDLIX_CALL_CONTEXT_ID=dialbase-global
```

Replace `REVERB_APP_KEY` and `REVERB_APP_SECRET` with your own values. For example, generate each locally with `php -r 'echo bin2hex(random_bytes(32)), PHP_EOL;'`. Keep one shared calling context for users who should be able to call each other.

## Start Locally

```sh
composer dev
```

The development command starts Laravel, frontend assets, queue processing and Reverb. Open `http://localhost:8000`. Alternatively, let Herd serve Laravel and run `npm run dev` plus `php artisan reverb:start --host=127.0.0.1` in separate terminals. Do not start two Reverb instances on the same port.

The example uses HTTP/WS on localhost, which browsers allow for local microphone testing. With Herd HTTPS, use your secured hostname for `APP_URL`, `REVERB_HOST` and the corresponding Vite settings, and set `REVERB_SCHEME=https`. Rebuild assets after changing Vite variables.

`MAIL_MAILER=log` is intended only for development. Register a new account, open its verification link from `storage/logs/laravel.log` while signed in, then return to the dashboard. For external testers, configure a real mail service. Logs contain verification/reset links: never publish them.

## Test With Two Users

1. Register and verify two different accounts on this backend.
2. Sign in using two separate browser profiles, or a browser and the Flutter app.
3. Keep both clients open, allow microphone access and wait for online/ready status.
4. Call the other user, answer the incoming popup/screen and speak in both directions.
5. Try mute, speaker on mobile, minimize, end, decline and tap-to-redial from mobile history.
6. Confirm both users see their own history. Use headphones to avoid feedback when testing on one computer.

For testing across different networks, deploy this backend and Reverb on reachable HTTPS/WSS hosts with valid certificates. Set `APP_ENV=production`, `APP_DEBUG=false`, configure mail and persistent storage, supervise Reverb/queue processes and expose the correct WSS port through the reverse proxy/firewall. Configure the Flutter app with the public `/api/v1` URL. `localhost` and Herd `.test` domains are not remote-phone addresses. Dialbase session credentials, not Reverb, provide the audio NAT traversal servers.

## Follow the Code

Start with [CALLING.md](CALLING.md) for the web/native flow and its lifecycle rules. [API.md](API.md) documents mobile authentication, directory, session, presence and history endpoints. `CallSessionController` exchanges backend credentials for a session; `call-session.js` maintains signaling; `calls.js` performs WebRTC negotiation; `call-window.js` renders the incoming and active call controls.

Call history is client-reported demo data, not a billing ledger. This demo supports foreground calling only. PushKit/APNs, FCM, CallKit and production incoming-call delivery while the app is suspended are intentionally outside its scope. Browser autoplay restrictions may require an initial interaction before ringtone playback.

## Checks

```sh
php artisan test
npm run test:calling
npm run build
```

Tests use isolated fixtures and mocked signaling; they do not contain the live SQLite users or make real Dialbase calls. Keep the lifecycle tests when modifying signaling: receipts, stale events and microphone-permission races can otherwise break active calls.

## Local Data

Migrations and `.env.example` define the installation; runtime databases and
credentials are not repository assets. Each checkout creates its own database
and accounts. Ignore rules exclude environment files, databases, logs, caches,
uploads and signing keys. They do not remove files already tracked by Git.
