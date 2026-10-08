# Calling Screen QA

Final result: passed for the app-owned call screen layout and controls.

Reference: the supplied iPhone screenshot, `Simulator Screenshot - iPhone 17 - 2026-10-06 at 21.43.55.png`.

Rendered comparison: `test/features/calling/goldens/connected_call.png`, captured from Flutter's renderer at 402 x 874 with actual SDK fonts. The connected state uses Test Contact and 00:03 to match the reference. OS status bars and the Dynamic Island are device-owned and are not drawn by the app.

Confirmed grey full-screen background, dark circular initial avatar, white name/status, circular speaker/mute controls and red end-call control. Minimize returns to the app without ending the call. Incoming state replaces audio controls with Answer and Decline.

Widget tests check control callbacks and layout at 320 x 568 and 852 x 393 with larger text. Compact/landscape layouts scroll rather than overlap controls with the caller information. No P0/P1/P2 visual issues remained in these checks.

Native iOS simulator build passed. The screenshot comparison is renderer-based, not a real connected-call capture. Actual two-device audio, OS audio-route behavior and background incoming calls have not been validated by this report.
