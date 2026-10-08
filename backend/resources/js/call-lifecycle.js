export function matchesCall(call, data) {
    return Boolean(call?.callUuid && data.call_uuid === call.callUuid);
}

export async function acquireCallMedia(call, isCurrent, mediaDevices) {
    const stream = await mediaDevices.getUserMedia({ audio: true, video: false });
    // Permission dialogs can outlive the call that opened them.
    if (!isCurrent(call)) {
        stream.getTracks().forEach((track) => track.stop());
        return null;
    }
    return stream;
}
