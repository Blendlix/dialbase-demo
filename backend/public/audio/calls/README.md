# Call Sounds

Place optional browser-supported audio files in this folder:

- `outgoing-ringing.mp3` plays for the caller while waiting for an answer.
- `incoming-ringtone.mp3` plays for the recipient while the call is ringing.

If either file is absent or cannot be played, the dashboard uses a generated tone instead.
Sounds default to enabled. Browsers may require a click or keypress before audio can play; the dashboard retries on that gesture.

The demo includes both MP3s and uses generated tones if playback fails.

The paths can be changed with `VITE_CALL_OUTGOING_RINGTONE` and `VITE_CALL_INCOMING_RINGTONE` in `.env`.

## Asset License

A redistribution license for the bundled MP3 recordings has not yet been
documented. They are not covered by the source-code MIT license. Generated
fallback tones do not require these recordings.
