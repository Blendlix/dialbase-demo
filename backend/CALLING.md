# Calling integration

The app uses two independent realtime connections:

- Laravel Reverb reports presence and broadcasts browser availability.
- Dialbase authorizes calls, relays signaling and supplies STUN/TURN credentials.

A user is callable only when their Reverb presence is online, their Dialbase
session is authenticated, and they are not already handling a call. Availability
is announced every 10 seconds and expires after 25 seconds without an update.
These browser announcements control the UI; Dialbase still enforces call rules.

## Files

- `resources/js/calls.js`: dashboard controls, call state, WebRTC and local history.
- `resources/js/call-session.js`: authentication, token refresh and reconnect backoff.
- `resources/js/call-realtime.js`: Reverb presence and availability announcements.
- `resources/js/call-lifecycle.js`: call ID matching and cancel-safe microphone capture.
- `resources/js/call-window.js`: incoming modal, active controls and minimized call dock.
- `app/Http/Controllers/CallSessionController.php`: exchanges backend credentials
  for a browser session. Project secrets never enter the browser response.

## Changing the call flow

Associate outgoing responses with `request_id`. Once the invitation response
assigns `call_uuid`, require that ID on media and terminal events. Do not let a
late event from a previous call affect the current call.

After awaiting browser permission or WebRTC operations, check that the call is
still current. A user can cancel while a permission dialog is open. Stop any
stream that arrives after cancellation.

Refresh the session before token expiry and wait for `session.refreshed` before
continuing. TURN credentials expire separately, so starting or accepting a call
also refreshes credentials that are at least eight minutes old. Use the latest
ICE configuration when creating a peer connection.

Every terminal path must release microphone tracks, close the peer connection,
stop ringtones and restore controls. A disconnected signaling socket disables
calling until authentication succeeds again.

## Verification

Run `npm run test:calling` for the Node tests and `php vendor/bin/pest` for backend
tests. Run `npm run build` after frontend changes.

The Node tests mock DOM, sockets and media. They cover state and timing but do
not verify audible calls. Validate audio with two authenticated browser profiles,
including Wi-Fi to mobile data, microphone cancellation, busy peers and network
loss. Call history is client-reported and should not be used for billing.

## Local realtime server

Herd serves the Laravel app, but Reverb still needs its own running process.
`composer dev` includes Reverb in the registered development processes. To run
only Reverb, use `php artisan reverb:start --host=127.0.0.1` from the project root.
Run one Reverb instance per configured port.

The example environment uses `ws://localhost:8080` for local browser testing.
For Herd HTTPS, set the app URL and Reverb hostname to your secured `.test`
domain and use the HTTPS scheme. Reverb can resolve the existing Herd certificate;
keep the hostname and TLS scheme consistent with the `VITE_REVERB_*` values.
For remote phones, use a reachable public HTTPS/WSS deployment. Rebuild assets
after changing frontend environment variables.

## Reading the flow

Registration, login, email verification, user discovery and demo history belong
to Laravel. Reverb supplies presence; it does not carry microphone audio.
Dialbase owns calling authorization, call events and signaling transport. The
browser/native WebRTC engine carries audio using the supplied STUN/TURN servers.

Follow `inviteUser`, `answerCall`, `handleMessage` and `preparePeerConnection`
in `calls.js` for the web path. The Flutter equivalents are `call`, `answer`,
`_onMessage` and `_prepareMedia` in its calling controller. Session controllers
derive the user identity on the server and never expose the Dialbase product secret.

Dialbase's `webrtc.*` forwarding receipt contains `forwarded: true` without
an SDP/candidate. It is an acknowledgement, not a peer media message.

Calling initializes again on Livewire navigation and releases the old session
when leaving the dashboard. Minimizing the call window keeps the call running
on the current page; it does not transfer the call to a different page.

Call sounds default to enabled when the dashboard mounts. The client attempts
to unlock audio immediately and retries on a trusted pointer or keyboard event
if autoplay is blocked. The sound toggle overrides automatic retries for the
current dashboard session. Leaving the page closes the ringtone audio context.
