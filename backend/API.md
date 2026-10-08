# Demo API

This API belongs to the Laravel demo. It supplies app authentication, a user
directory, temporary Dialbase sessions and client-reported call history.
Dialbase handles call invitations and media signaling over its own WebSocket.

## Setup

Run `composer install` and `php artisan migrate`. Configure the Dialbase
credentials in `.env` and run Reverb for live presence. Use HTTPS outside local
development. All examples below use `/api/v1` relative to this demo's host.

Send `Accept: application/json` and `Content-Type: application/json`. Protected
requests also require `Authorization: Bearer <access_token>`.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/auth/register` | Create an account and a demo access token |
| POST | `/auth/login` | Sign in and create a demo access token |
| POST | `/auth/forgot-password` | Send the existing web password-reset link |
| POST | `/auth/logout` | Revoke the current access token |
| GET | `/me` | Read the authenticated account |
| POST | `/auth/email/verification-notification` | Resend the verification email |
| GET | `/users?search=Amina&per_page=25` | Paginated verified users, excluding yourself |
| POST | `/calls/session` | Request a temporary Dialbase calling session |
| GET | `/calls/config` | Public Reverb connection settings for native clients |
| GET | `/calls/history` | Read your latest 100 history records |
| POST | `/calls/history` | Record an incoming or outgoing call |
| PATCH | `/calls/history/{id}` | Update your own record's status |
| POST | `/broadcasting/auth` | Authorize a Reverb presence subscription |

Users, sessions, history and presence require a verified email. Registration
sends the existing web verification link: sign into the web demo and follow
that link before calling. Tokens expire after 24 hours. Logging out revokes
only the current device token. Password-only API login rejects accounts with
two-factor authentication; use the existing web sign-in flow for those accounts.

## Register and sign in

Registration body:

```json
{
  "name": "Amina",
  "email": "amina@example.com",
  "password": "your-password",
  "password_confirmation": "your-password",
  "device_name": "My mobile app"
}
```

Login uses `email`, `password` and `device_name`. Both endpoints return
`access_token`, `token_type`, `expires_at` and your `user` object. The access
token authenticates requests to this demo; it is not a Dialbase session token.

## Start a call

1. Sign in and verify the account's email.
2. Fetch `/users` to select a peer.
3. POST `/calls/session` with an empty JSON object. Identity and context come
   from the signed-in account and server configuration, not client input.
4. Use the returned `ws_url`, `token` and `ice_servers` to connect to Dialbase
   and create the WebRTC peer connection. Both users need authenticated sessions.
5. Wait for `auth.ok`, then send `call.invite` to the peer.
6. The callee receives `call.ringing` and sends `call.accept` or `call.reject`.
7. On acceptance, exchange WebRTC offer, answer and ICE candidates.
8. Send `call.connected` only once audio connects; finish with `call.end`.

Example invitation on the Dialbase WebSocket:

```json
{
  "event": "call.invite",
  "request_id": "a-unique-request-id",
  "data": {
    "callee_user_id": "42",
    "callee_role": "user",
    "context_type": "application",
    "context_id": "dialbase-global"
  }
}
```

Use the actual role and context from the session response. Subsequent call
actions use the returned `call_uuid`. There are no REST invite/accept/end routes
in this demo: those actions use Dialbase signaling. See `resources/js/calls.js`
and `resources/js/call-session.js` for the complete browser flow.

## Presence and history

For Reverb, POST `socket_id` and `channel_name: "presence-calls"` to
`/broadcasting/auth` with the demo access token. Connect to this demo's Reverb
host and public app key, not Dialbase's `ws_url`. Directory results do not claim
users are online; follow presence and availability events for call readiness.

History creation accepts `peer_user_id`, `direction` (`incoming` or `outgoing`)
and optional `call_uuid`. Updates accept `status` and optional `call_uuid`.
Supported statuses: `ringing`, `accepted`, `connected`, `ended`, `canceled`,
`rejected`, `missed`, `failed`. History is client-reported, not billing evidence.

Errors use Laravel JSON responses: 401 for authentication, 403 for unverified
email or channel authorization, 404 for another user's history, 422 for invalid
input, 429 for throttling, and 502/503 for calling-service failures.

Run `php vendor/bin/pest --filter=DemoApiTest` to test the API without making
real calls to Dialbase.
