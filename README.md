# Dialbase Demo

Learn how to connect web and native clients to Dialbase audio calls.

This repository contains two clients of the same demo backend:

- [`backend/`](backend/README.md): Laravel API, registration, Reverb presence and the web dashboard.
- [`app/`](app/README.md): Flutter native app, audio-call screen and recent-call redial.

## Before You Start

- Git, PHP 8.3+ with SQLite/PDO SQLite, Composer, Node.js 22.12+ and npm.
- A Dialbase product key ID and secret from your Dialbase account. Without these,
  registration works but calls cannot start.
- For the native app: Flutter with Dart 3.13.3 or compatible newer Dart 3.x,
  plus Android SDK/JDK for Android or Xcode on macOS for iOS.

The commands below use a macOS/Linux shell. Run them in the stated directory.
Do not copy the example credentials literally: replace the marked values.

## 1. Clone the Repository

```sh
git clone https://github.com/Blendlix/dialbase-demo.git
cd dialbase-demo/backend
composer install
cp .env.example .env
php artisan key:generate
```

You are now in `backend/`. Keep the generated `APP_KEY` in `.env`; do not
regenerate it when updating an existing installation.

## 2. Configure the Backend

Open `backend/.env` in your editor. Set these values for local web testing:

```dotenv
APP_ENV=local
APP_DEBUG=true
APP_URL=http://localhost:8000
DB_CONNECTION=sqlite
BROADCAST_CONNECTION=reverb
QUEUE_CONNECTION=database
MAIL_MAILER=log

BLENDLIX_CALL_BASE_URL=https://rtc-svc.blendlix.com
BLENDLIX_CALL_PRODUCT_KEY_ID=your-dialbase-product-key-id
BLENDLIX_CALL_PRODUCT_SECRET=your-dialbase-product-secret
BLENDLIX_CALL_CONTEXT_ID=dialbase-global

REVERB_APP_ID=dialbase-demo
REVERB_APP_KEY=your-generated-reverb-key
REVERB_APP_SECRET=your-generated-reverb-secret
REVERB_HOST=localhost
REVERB_PORT=8080
REVERB_SCHEME=http
REVERB_SERVER_HOST=0.0.0.0
REVERB_SERVER_PORT=8080
VITE_REVERB_APP_KEY="${REVERB_APP_KEY}"
VITE_REVERB_HOST="${REVERB_HOST}"
VITE_REVERB_PORT="${REVERB_PORT}"
VITE_REVERB_SCHEME="${REVERB_SCHEME}"
```

Generate two different random values by running this command twice. Paste the
first output into `REVERB_APP_KEY` and the second into `REVERB_APP_SECRET`:

```sh
php -r 'echo bin2hex(random_bytes(32)), PHP_EOL;'
```

Reverb credentials are created locally, not obtained from Dialbase. The Reverb
key is public; its secret and the Dialbase product secret stay on the backend.
Leave `DB_DATABASE` unset to use Laravel's `database/database.sqlite` default.
Use the same calling context for accounts that should call each other.

## 3. Create Tables and Build the Web Client

Still in `backend/`, run:

```sh
php -r 'file_exists("database/database.sqlite") || touch("database/database.sqlite");'
php artisan migrate
php artisan optimize:clear
npm ci
npm run build
```

This creates an empty database, not sample users. Do not run `migrate:fresh` on
an installation whose data you want to keep.

## 4. Start Laravel and Reverb

In the same terminal, from `backend/`:

```sh
composer dev
```

Keep this terminal open. It starts Laravel on port 8000, Reverb on port 8080,
the queue worker and the frontend dev server. Open **http://localhost:8000**,
not the Vite server URL. Stop the processes with Ctrl+C.

For separate terminals instead of `composer dev`, run each of the following
from `backend/` in its own terminal:

```sh
php artisan serve --host=127.0.0.1 --port=8000
```

```sh
php artisan reverb:start --host=127.0.0.1 --port=8080
```

```sh
php artisan queue:work --tries=1
```

```sh
npm run dev
```

Choose one method, not both. If a port is already occupied, stop that old demo
process or change the port and matching `.env` values. After changing `.env`,
run `php artisan optimize:clear` and restart the processes. Rebuild assets with
`npm run build` when using built assets rather than the frontend dev server.

## 5. Register and Verify Two Accounts

1. Open `http://localhost:8000/register` in browser profile A and register user A.
2. In another terminal, from `backend/`, run `tail -f storage/logs/laravel.log`.
3. Find the verification email's URL containing `/email/verify/`. Open that
   complete URL in profile A while signed in. Then open `/dashboard`.
4. Open a separate browser profile or private window and register user B.
5. Find user B's verification URL in the log and open it in user B's browser.
6. Keep both dashboards open. Both users should appear online and ready.

`MAIL_MAILER=log` writes development emails to the log instead of delivering
them. If needed, use the verification page's resend action and watch the log
again. Never publish this log: its links are private. Configure a real mail
service before inviting remote testers.

## 6. Make the First Web Call

In user A's dashboard, call user B. Allow microphone access in both browsers;
user B should see the incoming popup and can answer or decline. After answering,
speak in both directions, try mute, minimize/restore and end the call. Check
history afterwards. Use headphones if both browsers run on the same computer.

Click the dashboard once if the browser blocks ringtone autoplay. Localhost is
allowed for browser microphone testing; a non-local web address needs HTTPS.

## 7. Connect the Flutter App

First choose a backend address that the phone or simulator can actually reach.
The local web setup above is not a remote-phone deployment. A phone cannot reach
your computer through `localhost`, and Android does not resolve Herd `.test`
domains automatically. The recommended device-testing setup is a reachable
HTTPS backend and WSS Reverb endpoint with trusted certificates.

On that backend, configure the public addresses, for example:

```dotenv
APP_URL=https://demo.your-domain.com
REVERB_HOST=reverb.your-domain.com
REVERB_PORT=443
REVERB_SCHEME=https
REVERB_SERVER_HOST=0.0.0.0
REVERB_SERVER_PORT=8080
```

These are example addresses, not included hosting. Configure DNS and a TLS
reverse proxy for your own hosts: the Reverb public WSS endpoint must forward
WebSocket upgrades to the Reverb process on port 8080. Keep its key/secret
unchanged. The `VITE_REVERB_*` references above inherit these public settings.
Rebuild assets, clear cached config and restart Reverb after changing them.
On a public deployment also set `APP_ENV=production`, `APP_DEBUG=false`, real
mail delivery and supervised queue/Reverb processes. Start Reverb separately
there; the local `composer dev` convenience command is not a production service.

From the repository root, in a new terminal:

```sh
cd app
flutter doctor
flutter pub get
cp config/development.example.json config/development.json
```

Resolve any Android/iOS toolchain issues reported by `flutter doctor`. Edit
`app/config/development.json` to point to YOUR Laravel backend, including `/api/v1`:

```json
{
  "DIALBASE_API_URL": "https://demo.your-domain.com/api/v1"
}
```

Do not use the Dialbase management dashboard URL here, and do not put product
keys in this file. List devices, then replace `YOUR_DEVICE_ID` with one from the
output and run the app:

```sh
flutter devices
flutter run -d YOUR_DEVICE_ID --dart-define-from-file=config/development.json
```

For an iOS simulator, start it first with `open -a Simulator` on macOS. A physical
iPhone needs your own signing team and Bundle ID in `ios/Runner.xcworkspace`.
For local Herd HTTPS on a simulator, trust the Herd CA on that simulator before
connecting; do not bypass certificate verification.

Sign in with a verified account from this same backend. Use another verified
account on the web or another phone. Keep both clients in the foreground, allow
the microphone, wait for ready status, then call and answer. Test speaker, mute,
timer, end and tap a recent call to redial. Background calls/CallKit are not
included in this demo.

## 8. Build an Android Test APK

From `app/`, with the reachable HTTPS backend configured:

```sh
flutter build apk --release --dart-define-from-file=config/development.json
```

Send `app/build/app/outputs/flutter-apk/app-release.apk` to your tester and
install it with Android's sideload permission. This demo uses debug signing
for testing, not Play Store release signing. If you change the backend URL,
rebuild the APK. A friend's phone also needs access to the public Reverb WSS host.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Website does not open | Laravel terminal is running; open port 8000, not the Vite port. |
| Missing SQLite tables | Run `php artisan migrate` from `backend/`; check PHP SQLite support. |
| Account cannot access calls | Verify the email on this backend, then sign in again. |
| Live updates unavailable / user offline | Reverb is running; host, port, scheme and app key match; restart after env changes. For phones, the advertised host must be reachable. |
| Session or calling authorization fails | Check your Dialbase product key ID, secret and shared context; inspect the local Laravel log without publishing it. |
| App cannot connect / certificate error | Use the backend `/api/v1` URL, a reachable host and trusted HTTPS certificate. Localhost on a phone is the phone itself. |
| No audio | Allow microphones, keep clients open, unmute and test headphones. Check network access to the ICE servers returned by Dialbase. |
| No ringtone | Interact with the browser once and check the sound toggle/device volume. |

For API endpoints and request examples, see [backend/API.md](backend/API.md).
For the implementation flow, see [backend/CALLING.md](backend/CALLING.md).

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
