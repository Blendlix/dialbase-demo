export function createCallWindow(app) {
    const dialog = app.querySelector('[data-call-panel]');
    const restore = app.querySelector('[data-call-restore]');
    const minimize = app.querySelector('[data-call-minimize]');
    const name = app.querySelector('[data-call-peer]');
    const avatar = app.querySelector('[data-call-avatar]');
    const phase = app.querySelector('[data-call-phase]');
    const duration = app.querySelector('[data-call-duration]');
    const miniDuration = app.querySelector('[data-call-mini-duration]');
    const mute = app.querySelector('[data-call-mute]');
    const accept = app.querySelector('[data-call-accept]');
    const reject = app.querySelector('[data-call-reject]');
    const end = app.querySelector('[data-call-end]');
    const audioPlay = app.querySelector('[data-call-play-audio]');
    let currentCall;
    let minimized = false;

    const open = () => {
        minimized = false;
        restore.hidden = true;
        dialog.hidden = false;
        if (!dialog.open) dialog.showModal();
        if (dialog.dataset.mode === 'incoming') accept.focus();
        else if (!mute.hidden) mute.focus();
        else end.focus();
    };

    minimize.addEventListener('click', () => {
        if (!currentCall || dialog.dataset.mode === 'incoming') return;
        minimized = true;
        dialog.close();
        restore.hidden = false;
        restore.focus();
    });
    restore.addEventListener('click', open);
    dialog.addEventListener('cancel', (event) => {
        // Ending a call always requires an explicit call action.
        event.preventDefault();
    });

    const setMuted = (muted) => {
        mute.setAttribute('aria-pressed', String(muted));
        mute.title = muted ? 'Unmute microphone' : 'Mute microphone';
        mute.querySelector('[data-call-mute-label]').textContent = muted ? 'Unmute' : 'Mute';
        mute.querySelector('[data-call-mic-on]').hidden = muted;
        mute.querySelector('[data-call-mic-off]').hidden = !muted;
    };

    return {
        show(call, { incoming = false, canEnd = false } = {}) {
            if (currentCall !== call) minimized = false;
            currentCall = call;
            dialog.dataset.mode = incoming ? 'incoming' : call.accepted ? 'active' : 'outgoing';
            name.textContent = call.peerName;
            avatar.textContent = call.peerName
                .trim()
                .split(/\s+/)
                .slice(0, 2)
                .map((part) => part[0])
                .join('')
                .toUpperCase();
            phase.textContent = incoming ? 'Incoming audio call' : call.accepted ? 'Audio call' : 'Calling';
            app.querySelector('[data-call-mini-name]').textContent = call.peerName;
            accept.hidden = reject.hidden = !incoming;
            end.hidden = !canEnd;
            minimize.hidden = incoming;
            if (!minimized) open();
        },
        setStatus(message) {
            app.querySelector('[data-call-dialog-status]').textContent = message;
        },
        setDuration(value) {
            duration.textContent = miniDuration.textContent = value;
        },
        setEndLabel(label) {
            end.querySelector('[data-call-end-label]').textContent = label;
            end.title = label === 'Cancel' ? 'Cancel call' : 'End call';
        },
        setMuted,
        close() {
            currentCall = undefined;
            minimized = false;
            if (dialog.open) dialog.close();
            dialog.hidden = true;
            restore.hidden = true;
            audioPlay.hidden = true;
            setMuted(false);
        },
    };
}
