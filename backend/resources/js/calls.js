import { joinCallPresence } from './call-realtime.js';
import { createCallSounds } from './call-sounds.js';
import { createCallSession } from './call-session.js';
import { acquireCallMedia, matchesCall } from './call-lifecycle.js';
import { createCallWindow } from './call-window.js';

let mountedApp;
let disposeCalling = () => {};

function initializeCalling() {
    const app = document.querySelector('[data-call-app]');
    if (app === mountedApp) return;
    disposeCalling();
    mountedApp = app;
    disposeCalling = () => {};

    if (app) {
        const status = app.querySelector('[data-call-status]');
        const realtimeStatus = app.querySelector('[data-realtime-status]');
        const historyList = app.querySelector('[data-call-history-list]');
        const soundToggleButton = app.querySelector('[data-call-sound-toggle]');
        const callWindow = createCallWindow(app);
        const durationLabel = app.querySelector('[data-call-duration]');
        const acceptButton = app.querySelector('[data-call-accept]');
        const rejectButton = app.querySelector('[data-call-reject]');
        const endButton = app.querySelector('[data-call-end]');
        const muteButton = app.querySelector('[data-call-mute]');
        const remoteAudio = app.querySelector('[data-call-audio]');
        const callButtons = [...app.querySelectorAll('[data-call-user-id]')];
        const callSounds = createCallSounds({
            outgoing: import.meta.env.VITE_CALL_OUTGOING_RINGTONE || '/audio/calls/outgoing-ringing.mp3',
            incoming: import.meta.env.VITE_CALL_INCOMING_RINGTONE || '/audio/calls/incoming-ringtone.mp3',
        });

        let session;
        let signaling;
        let peerConnection;
        let localStream;
        let activeCall;
        let connected = false;
        let connectionAnnounced = false;
        let pendingCandidates = [];
        let presence;
        let timerInterval;
        let callStartedAt;
        let isMuted = false;
        let callSoundsManuallyDisabled = false;
        let soundUnlockAttempt = 0;
        let disposed = false;
        const peerCallStates = new Map();
        const peerStateTimers = new Map();
        const peerAvailability = new Map();
        const pendingRequests = new Map();
        let preparingCall;
        let mediaPromise;
        const availablePeer = (id) => {
            const peer = peerAvailability.get(String(id));
            return userIsOnline(id) && peer?.ready && !peer.busy && Date.now() - peer.seenAt < 25000;
        };
        const updateAvailability = () => {
            presence?.setAvailability({ ready: connected, busy: Boolean(activeCall) });
            callButtons.forEach((button) => {
                button.disabled = !connected || Boolean(activeCall) || !availablePeer(button.dataset.callUserId);
            });
        };

        const userIsOnline = (userId) =>
            Boolean(app.querySelector(`[data-user-live-status="${CSS.escape(String(userId))}"]`)?.dataset.online);

        const updateUserStatus = (userId, callState = peerCallStates.get(String(userId)) ?? null) => {
            const badge = app.querySelector(`[data-user-live-status="${CSS.escape(String(userId))}"]`);

            if (!badge) {
                return;
            }

            const labels = {
                calling: 'Calling...',
                ringing: 'Incoming call',
                answering: 'Answering...',
                answered: 'Connecting...',
                connected: 'On call',
                declined: 'Call declined',
                missed: 'Missed call',
                ended: 'Call ended',
            };

            const availability = peerAvailability.get(String(userId));
            const ready = availability?.ready && Date.now() - availability.seenAt < 25000;
            badge.textContent =
                labels[callState] ??
                (userIsOnline(userId) && ready ? (availability.busy ? 'On call' : 'Online') : 'Offline');
            badge.classList.toggle(
                'text-emerald-600',
                callState === 'connected' || (!callState && userIsOnline(userId)),
            );
            badge.classList.toggle(
                'dark:text-emerald-400',
                callState === 'connected' || (!callState && userIsOnline(userId)),
            );
            badge.classList.toggle('text-neutral-500', !callState || callState !== 'connected');
            badge.classList.toggle('dark:text-neutral-400', !callState || callState !== 'connected');
        };

        const setPeerCallState = (userId, state) => {
            const key = String(userId);
            const terminalStates = new Set(['declined', 'missed', 'ended']);

            window.clearTimeout(peerStateTimers.get(key));

            if (terminalStates.has(state)) {
                peerCallStates.set(key, state);
                updateUserStatus(key);
                peerStateTimers.set(
                    key,
                    window.setTimeout(() => {
                        peerCallStates.delete(key);
                        updateUserStatus(key);
                    }, 5000),
                );
                return;
            }

            peerCallStates.set(key, state);
            updateUserStatus(key);
        };

        const broadcastCallState = (state, details = {}) => {
            if (presence && activeCall?.peerId) {
                presence.whisper(activeCall.peerId, state, {
                    call_uuid: activeCall.callUuid ?? null,
                    started_at: callStartedAt ? new Date(callStartedAt).toISOString() : null,
                    ...details,
                });
            }
        };

        const formatDuration = (seconds) => {
            const hours = Math.floor(seconds / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            const remainder = seconds % 60;
            const pad = (value) => String(value).padStart(2, '0');

            return hours > 0 ? `${pad(hours)}:${pad(minutes)}:${pad(remainder)}` : `${pad(minutes)}:${pad(remainder)}`;
        };

        const formatHistoryDate = (value) =>
            new Intl.DateTimeFormat(undefined, {
                dateStyle: 'medium',
                timeStyle: 'short',
            }).format(new Date(value));

        const renderHistory = (history) => {
            app.querySelector('[data-history-empty]')?.remove();

            let row = historyList.querySelector(`[data-history-id="${CSS.escape(String(history.id))}"]`);

            if (!row) {
                row = document.createElement('article');
                row.className =
                    'flex flex-wrap items-center justify-between gap-x-6 gap-y-2 border-b border-neutral-200 px-4 py-3 last:border-b-0 dark:border-neutral-700';
                row.dataset.historyId = history.id;

                const identity = document.createElement('div');
                identity.className = 'min-w-0';
                const name = document.createElement('p');
                name.className = 'truncate font-medium text-neutral-900 dark:text-white';
                name.dataset.historyPeer = '';
                const meta = document.createElement('p');
                meta.className = 'mt-0.5 text-xs text-neutral-500 dark:text-neutral-400';
                meta.dataset.historyMeta = '';
                identity.append(name, meta);

                const result = document.createElement('div');
                result.className = 'flex shrink-0 items-center gap-4 text-sm';
                const callStatus = document.createElement('span');
                callStatus.className = 'text-neutral-600 dark:text-neutral-300';
                callStatus.dataset.historyStatus = '';
                const duration = document.createElement('time');
                duration.className = 'font-mono tabular-nums text-neutral-700 dark:text-neutral-200';
                duration.dataset.historyDuration = '';
                result.append(callStatus, duration);
                row.append(identity, result);
                historyList.prepend(row);
            }

            row.querySelector('[data-history-peer]').textContent = history.peer_name;
            row.querySelector('[data-history-meta]').textContent =
                `${history.direction[0].toUpperCase()}${history.direction.slice(1)} · ${formatHistoryDate(history.initiated_at)}`;
            row.querySelector('[data-history-status]').textContent =
                history.status[0].toUpperCase() + history.status.slice(1);
            row.querySelector('[data-history-duration]').textContent = formatDuration(history.duration_seconds);
        };

        const createCallHistory = async (call, direction) => {
            try {
                const response = await fetch(app.dataset.historyUrl, {
                    method: 'POST',
                    credentials: 'same-origin',
                    headers: {
                        Accept: 'application/json',
                        'Content-Type': 'application/json',
                        'X-CSRF-TOKEN': app.dataset.csrfToken,
                    },
                    body: JSON.stringify({
                        peer_user_id: call.peerId,
                        direction,
                        call_uuid: call.callUuid ?? null,
                    }),
                });
                const result = await response.json();

                if (!response.ok) {
                    throw new Error(result.message || 'Could not save call history.');
                }

                call.historyId = result.data.id;
                renderHistory(result.data);

                if (call.pendingHistoryStatus) {
                    await persistCallHistoryStatus(call, call.pendingHistoryStatus);
                }
            } catch (error) {
                console.error('Call history could not be saved.', error);
            }
        };

        const persistCallHistoryStatus = async (call, nextStatus) => {
            if (!call) {
                return;
            }

            call.pendingHistoryStatus = nextStatus;

            if (!call.historyId) {
                return;
            }

            try {
                const response = await fetch(`${app.dataset.historyUrl}/${call.historyId}`, {
                    method: 'PATCH',
                    credentials: 'same-origin',
                    headers: {
                        Accept: 'application/json',
                        'Content-Type': 'application/json',
                        'X-CSRF-TOKEN': app.dataset.csrfToken,
                    },
                    body: JSON.stringify({
                        status: nextStatus,
                        call_uuid: call.callUuid ?? null,
                    }),
                });
                const result = await response.json();

                if (!response.ok) {
                    throw new Error(result.message || 'Could not update call history.');
                }

                renderHistory(result.data);
            } catch (error) {
                console.error('Call history could not be updated.', error);
            }
        };

        const updateCallHistory = (nextStatus) => persistCallHistoryStatus(activeCall, nextStatus);

        const startCallTimer = () => {
            if (!callStartedAt) {
                callStartedAt = Date.now();
            }

            durationLabel.hidden = false;
            window.clearInterval(timerInterval);

            const update = () => {
                callWindow.setDuration(formatDuration(Math.floor((Date.now() - callStartedAt) / 1000)));
            };

            update();
            timerInterval = window.setInterval(update, 1000);
        };

        const handlePeerCallState = (message) => {
            setPeerCallState(message.from_id, message.state);

            if (
                activeCall &&
                String(activeCall.peerId) === String(message.from_id) &&
                message.state === 'connected' &&
                message.started_at
            ) {
                callStartedAt = Date.parse(message.started_at) || callStartedAt;

                if (peerConnection?.connectionState === 'connected') {
                    startCallTimer();
                }
            }
        };

        const syncPresence = (users) => {
            const onlineIds = new Set(users.map((user) => String(user.id)));

            callButtons.forEach((button) => {
                const userId = String(button.dataset.callUserId);
                const badge = app.querySelector(`[data-user-live-status="${CSS.escape(userId)}"]`);

                if (badge) {
                    badge.dataset.online = onlineIds.has(userId) ? 'true' : '';
                    updateUserStatus(userId);
                }
            });
            updateAvailability();
        };

        presence = joinCallPresence(app.dataset.currentUserId, {
            onPresence: syncPresence,
            onPeerState: handlePeerCallState,
            onAvailability: (message) => {
                peerAvailability.set(String(message.user_id), {
                    ready: message.ready === true,
                    busy: message.busy === true,
                    seenAt: Date.now(),
                });
                updateUserStatus(message.user_id);
                updateAvailability();
            },
            onConnection: (isConnected) => {
                realtimeStatus.textContent = isConnected
                    ? 'Live updates connected.'
                    : 'Live updates disconnected. Reconnecting...';
            },
        });
        const availabilityTimer = setInterval(() => {
            callButtons.forEach((button) => updateUserStatus(button.dataset.callUserId));
            updateAvailability();
        }, 5000);

        const setStatus = (message) => {
            status.textContent = message;
            callWindow.setStatus(message);
        };

        const updateSoundToggle = () => {
            const enabled = callSounds.isEnabled();

            soundToggleButton.textContent = enabled ? 'Call sounds on' : 'Call sounds off';
            soundToggleButton.setAttribute('aria-pressed', String(enabled));
            soundToggleButton.title = enabled ? 'Turn off call sounds' : 'Turn on call sounds';
        };

        const removeSoundUnlockListeners = () => {
            document.removeEventListener('pointerdown', unlockSoundOnGesture, true);
            document.removeEventListener('keydown', unlockSoundOnGesture, true);
        };

        const enableCallSounds = ({ silent = false } = {}) => {
            const attempt = ++soundUnlockAttempt;
            const resume = callSounds.enable();
            updateSoundToggle();
            resume
                .then(() => {
                    if (disposed || callSoundsManuallyDisabled || attempt !== soundUnlockAttempt) return;
                    removeSoundUnlockListeners();

                    if (activeCall && !activeCall.connected) {
                        callSounds.play(activeCall.direction);
                    }
                })
                .catch(() => {
                    if (!silent && !disposed && attempt === soundUnlockAttempt) {
                        setStatus('Your browser could not enable call sounds. Check its audio settings.');
                    }
                });
        };

        const unlockSoundOnGesture = () => {
            if (!callSoundsManuallyDisabled) enableCallSounds({ silent: true });
        };

        // Autoplay may be blocked until a trusted user gesture occurs.
        document.addEventListener('pointerdown', unlockSoundOnGesture, true);
        document.addEventListener('keydown', unlockSoundOnGesture, true);
        enableCallSounds({ silent: true });

        soundToggleButton.addEventListener('click', () => {
            if (callSounds.isEnabled()) {
                callSounds.disable();
                callSoundsManuallyDisabled = true;
                soundUnlockAttempt++;
                updateSoundToggle();
                return;
            }

            callSoundsManuallyDisabled = false;
            enableCallSounds();
        });

        const send = (event, data) => {
            const requestId = signaling.send(event, data);
            if (!event.startsWith('webrtc.')) pendingRequests.set(requestId, { event, call: activeCall });
            return requestId;
        };

        const setCallButtonsDisabled = (disabled) => {
            callButtons.forEach((button) => {
                button.disabled = disabled || !availablePeer(button.dataset.callUserId);
            });
            presence?.setAvailability({ ready: connected, busy: Boolean(activeCall) });
        };

        const showCallPanel = ({ incoming = false, canEnd = false } = {}) => {
            callWindow.show(activeCall, { incoming, canEnd });
        };

        const cleanupCall = (message, peerState = 'ended', historyStatus = peerState) => {
            const peerId = activeCall?.peerId;

            callSounds.stop();

            if (peerId) {
                broadcastCallState(peerState);
                setPeerCallState(peerId, peerState);
                updateCallHistory(historyStatus);
            }

            window.clearInterval(timerInterval);
            timerInterval = undefined;
            callStartedAt = undefined;
            durationLabel.hidden = true;
            callWindow.setDuration('00:00');
            isMuted = false;
            callWindow.setMuted(false);
            muteButton.hidden = true;
            peerConnection?.close();
            peerConnection = undefined;
            localStream?.getTracks().forEach((track) => track.stop());
            localStream = undefined;
            remoteAudio.srcObject = null;
            activeCall = undefined;
            pendingRequests.clear();
            pendingCandidates = [];
            connectionAnnounced = false;
            callWindow.close();
            setCallButtonsDisabled(!connected);

            if (message) {
                setStatus(message);
            }
        };

        const flushCandidates = async (connection = peerConnection) => {
            if (!connection?.remoteDescription) {
                return;
            }

            const candidates = pendingCandidates;
            pendingCandidates = [];
            for (const candidate of candidates) {
                await connection.addIceCandidate(candidate);
            }
        };

        const preparePeerConnection = async (call = activeCall) => {
            if (peerConnection) {
                return;
            }

            if (!navigator.mediaDevices?.getUserMedia) {
                throw new Error('Audio calls require a secure browser connection and microphone access.');
            }

            if (preparingCall === call) return mediaPromise;
            preparingCall = call;
            mediaPromise = (async () => {
                const stream = await acquireCallMedia(
                    call,
                    (candidate) => activeCall === candidate && !candidate.cancelRequested,
                    navigator.mediaDevices,
                );
                if (!stream) return;
                localStream = stream;
                peerConnection = new RTCPeerConnection({ iceServers: signaling.getSession().ice_servers });
                localStream.getTracks().forEach((track) => peerConnection.addTrack(track, localStream));

                peerConnection.onicecandidate = ({ candidate }) => {
                    if (activeCall !== call) return;
                    if (candidate && activeCall?.callUuid) {
                        try {
                            send('webrtc.ice_candidate', {
                                call_uuid: activeCall.callUuid,
                                candidate: candidate.toJSON(),
                            });
                        } catch (error) {
                            setStatus(error.message);
                        }
                    }
                };

                peerConnection.ontrack = ({ streams, track }) => {
                    if (activeCall !== call) return;
                    remoteAudio.srcObject = streams[0] ?? new MediaStream([track]);
                    remoteAudio.play().catch(() => {
                        app.querySelector('[data-call-play-audio]').hidden = false;
                        setStatus('The call is connected. Enable audio playback in your browser.');
                    });
                };

                peerConnection.onconnectionstatechange = () => {
                    if (activeCall !== call) return;
                    if (peerConnection?.connectionState === 'connected' && !connectionAnnounced) {
                        connectionAnnounced = true;
                        activeCall.connected = true;
                        callSounds.stop();
                        startCallTimer();
                        updateCallHistory('connected');
                        muteButton.hidden = false;
                        setStatus(`Connected with ${activeCall.peerName}.`);
                        try {
                            send('call.connected', { call_uuid: activeCall.callUuid });
                        } catch (error) {
                            setStatus(error.message);
                        }
                        broadcastCallState('connected');
                        setPeerCallState(activeCall.peerId, 'connected');
                    } else if (peerConnection?.connectionState === 'failed') {
                        cleanupCall('The audio connection failed.', 'ended', 'failed');
                    }
                };
            })();
            try {
                await mediaPromise;
            } finally {
                if (preparingCall === call) {
                    preparingCall = undefined;
                    mediaPromise = undefined;
                }
            }
        };

        const inviteUser = async (button) => {
            if (!connected || activeCall || !availablePeer(button.dataset.callUserId)) {
                return;
            }

            const call = {
                direction: 'outgoing',
                peerId: button.dataset.callUserId,
                peerName: button.dataset.callUserName,
                inviteSent: false,
                cancelRequested: false,
            };
            activeCall = call;
            call.historyPromise = createCallHistory(call, 'outgoing');
            if (!callSounds.isEnabled() && !callSoundsManuallyDisabled) {
                enableCallSounds();
            }
            callSounds.play('outgoing');
            showCallPanel({ canEnd: true });
            callWindow.setEndLabel('Cancel');
            setStatus(`Calling ${activeCall.peerName}...`);
            broadcastCallState('calling');
            updateUserStatus(activeCall.peerId, 'calling');
            setCallButtonsDisabled(true);

            try {
                session = await signaling.ensureFresh();
                await call.historyPromise;
                if (activeCall !== call || call.cancelRequested) {
                    return;
                }

                await preparePeerConnection();
                if (activeCall !== call || call.cancelRequested) {
                    return;
                }

                call.inviteSent = true;
                send('call.invite', {
                    callee_user_id: activeCall.peerId,
                    callee_role: session.role,
                    context_type: session.context_type,
                    context_id: session.context_id,
                });
                updateCallHistory('ringing');
            } catch (error) {
                if (activeCall === call) cleanupCall(error.message || 'Could not start the call.', 'ended', 'failed');
            }
        };

        const cancelOrEndCall = () => {
            if (!activeCall) {
                return;
            }

            if (activeCall.direction === 'outgoing' && !activeCall.accepted) {
                if (!activeCall.inviteSent) {
                    cleanupCall('Call canceled.', 'ended', 'canceled');
                    return;
                }

                if (!activeCall.callUuid) {
                    activeCall.cancelRequested = true;
                    callSounds.stop();
                    peerConnection?.close();
                    peerConnection = undefined;
                    localStream?.getTracks().forEach((track) => track.stop());
                    localStream = undefined;
                    setStatus('Canceling call...');
                    showCallPanel();
                    setCallButtonsDisabled(true);
                    return;
                }

                try {
                    send('call.cancel', { call_uuid: activeCall.callUuid });
                } finally {
                    cleanupCall('Call canceled.', 'ended', 'canceled');
                }
                return;
            }

            try {
                if (activeCall.callUuid) send('call.end', { call_uuid: activeCall.callUuid });
            } finally {
                cleanupCall('Call ended.');
            }
        };

        const answerCall = async () => {
            if (!activeCall?.callUuid) {
                return;
            }

            callSounds.stop();
            const call = activeCall;
            acceptButton.disabled = true;

            try {
                session = await signaling.ensureFresh();
                if (activeCall !== call) return;
                await preparePeerConnection(call);
                if (activeCall !== call) return;
                send('call.accept', { call_uuid: activeCall.callUuid });
                activeCall.accepted = true;
                updateCallHistory('accepted');
                showCallPanel({ canEnd: true });
                callWindow.setEndLabel('End call');
                setStatus(`Connecting with ${activeCall.peerName}...`);
                broadcastCallState('answering');
                setPeerCallState(activeCall.peerId, 'answering');
            } catch (error) {
                if (activeCall !== call) return;
                try {
                    send('call.reject', { call_uuid: activeCall.callUuid });
                } catch {
                    // The call may already have ended.
                }

                cleanupCall(error.message || 'Could not answer the call.', 'declined', 'rejected');
            } finally {
                acceptButton.disabled = false;
            }
        };

        const handleOffer = async (data) => {
            if (!activeCall || !data.call_uuid || !data.sdp) {
                return;
            }

            if (!matchesCall(activeCall, data) || !activeCall.accepted) return;
            const call = activeCall;
            await preparePeerConnection(call);
            if (activeCall !== call) return;
            const connection = peerConnection;
            await connection.setRemoteDescription(new RTCSessionDescription(data.sdp));
            if (activeCall !== call) return;
            await flushCandidates(connection);
            if (activeCall !== call) return;

            const answer = await connection.createAnswer();
            if (activeCall !== call) return;
            await connection.setLocalDescription(answer);
            if (activeCall !== call) return;
            send('webrtc.answer', {
                call_uuid: activeCall.callUuid,
                sdp: connection.localDescription,
            });
        };

        const handleMessage = async (message) => {
            const data = message.data ?? {};
            const request = pendingRequests.get(message.request_id);
            if (request) pendingRequests.delete(message.request_id);

            if (message.event === 'error' || message.event === 'call.error') {
                if (!activeCall) {
                    setStatus(message.error?.message || data.message || 'Call service reported an error.');
                    return;
                }
                if (request?.call !== activeCall && !matchesCall(activeCall, data)) return;
                cleanupCall(
                    message.error?.message || data.message || 'The call could not be completed.',
                    'ended',
                    'failed',
                );
                return;
            }

            // The invite response assigns the ID before accept/cancel events arrive.
            if (
                request?.event === 'call.invite' &&
                request.call === activeCall &&
                message.success !== false &&
                data.call_uuid
            ) {
                activeCall.callUuid = data.call_uuid;
                if (activeCall.cancelRequested) {
                    send('call.cancel', { call_uuid: data.call_uuid });
                    cleanupCall('Call canceled.', 'ended', 'canceled');
                    return;
                }
            }

            const callEvent = message.event.startsWith('call.') || message.event.startsWith('webrtc.');
            if (callEvent && message.event !== 'call.ringing' && !matchesCall(activeCall, data)) return;

            switch (message.event) {
                case 'auth.ok':
                    connected = true;
                    setCallButtonsDisabled(false);
                    setStatus('Ready to call.');
                    break;
                case 'call.ringing':
                    if (activeCall) {
                        if (!matchesCall(activeCall, data))
                            signaling.send('call.reject', { call_uuid: data.call_uuid });
                        break;
                    }

                    activeCall = {
                        direction: 'incoming',
                        callUuid: data.call_uuid,
                        peerId: data.caller_user_id,
                        peerName: data.display_name || 'Unknown caller',
                    };
                    activeCall.historyPromise = createCallHistory(activeCall, 'incoming');
                    callSounds.play('incoming');
                    showCallPanel({ incoming: true });
                    broadcastCallState('ringing');
                    setPeerCallState(activeCall.peerId, 'ringing');
                    setCallButtonsDisabled(true);
                    setStatus(`${activeCall.peerName} is calling...`);
                    break;
                case 'call.accepted':
                    if (activeCall?.direction !== 'outgoing') {
                        break;
                    }

                    activeCall.callUuid = data.call_uuid;
                    if (activeCall.cancelRequested) {
                        send('call.cancel', { call_uuid: activeCall.callUuid });
                        cleanupCall('Call canceled.', 'ended', 'canceled');
                        break;
                    }

                    activeCall.accepted = true;
                    updateCallHistory('accepted');
                    callSounds.stop();
                    showCallPanel({ canEnd: true });
                    callWindow.setEndLabel('End call');
                    setStatus(`${activeCall.peerName} answered. Connecting...`);
                    broadcastCallState('answered');
                    setPeerCallState(activeCall.peerId, 'answered');

                    const acceptedCall = activeCall;
                    const connection = peerConnection;
                    const offer = await connection.createOffer();
                    if (activeCall !== acceptedCall) break;
                    await connection.setLocalDescription(offer);
                    if (activeCall !== acceptedCall) break;
                    send('webrtc.offer', {
                        call_uuid: activeCall.callUuid,
                        sdp: connection.localDescription,
                    });
                    break;
                case 'webrtc.offer':
                    await handleOffer(data);
                    break;
                case 'webrtc.answer':
                    if (peerConnection && data.sdp) {
                        await peerConnection.setRemoteDescription(new RTCSessionDescription(data.sdp));
                        await flushCandidates();
                    }
                    break;
                case 'webrtc.ice_candidate':
                    if (data.candidate) {
                        if (peerConnection?.remoteDescription) {
                            await peerConnection.addIceCandidate(data.candidate);
                        } else {
                            pendingCandidates.push(data.candidate);
                        }
                    }
                    break;
                case 'call.connected':
                    setStatus(`Connected with ${activeCall?.peerName ?? 'the other user'}.`);
                    break;
                case 'call.rejected':
                    cleanupCall('The call was declined.', 'declined', 'rejected');
                    break;
                case 'call.missed':
                    cleanupCall('The call was not answered.', 'missed', 'missed');
                    break;
                case 'call.ended':
                    cleanupCall('The call ended.', 'ended', 'ended');
                    break;
                case 'call.canceled':
                case 'call.cancelled':
                    cleanupCall('The call was canceled.', 'ended', 'canceled');
                    break;
                case 'call.error':
                case 'call.failed':
                    cleanupCall(
                        data.message || message.error?.message || 'The call could not be completed.',
                        'ended',
                        'failed',
                    );
                    break;
            }
        };

        callButtons.forEach((button) => {
            button.addEventListener('click', () => inviteUser(button));
        });

        acceptButton.addEventListener('click', answerCall);

        rejectButton.addEventListener('click', () => {
            try {
                if (activeCall?.callUuid) send('call.reject', { call_uuid: activeCall.callUuid });
            } finally {
                cleanupCall('Call declined.', 'declined', 'rejected');
            }
        });

        muteButton.addEventListener('click', () => {
            isMuted = !isMuted;
            localStream?.getAudioTracks().forEach((track) => {
                track.enabled = !isMuted;
            });
            callWindow.setMuted(isMuted);
            setStatus(isMuted ? 'Microphone muted.' : `Connected with ${activeCall?.peerName ?? 'the other user'}.`);
        });

        endButton.addEventListener('click', cancelOrEndCall);
        app.querySelector('[data-call-play-audio]').addEventListener('click', async () => {
            try {
                await remoteAudio.play();
                app.querySelector('[data-call-play-audio]').hidden = true;
            } catch {
                setStatus('Audio playback is unavailable. Check your browser audio settings.');
            }
        });

        signaling = createCallSession({
            requestSession: async () => {
                const response = await fetch(app.dataset.sessionUrl, {
                    method: 'POST',
                    credentials: 'same-origin',
                    headers: {
                        Accept: 'application/json',
                        'X-CSRF-TOKEN': app.dataset.csrfToken,
                    },
                });
                const result = await response.json();

                if (!response.ok) {
                    throw new Error(result.message || 'Could not connect to the call service.');
                }

                return result;
            },
            onReady: (nextSession) => {
                session = nextSession;
                connected = true;
                updateAvailability();
                setStatus('Ready to call.');
            },
            onMessage: async (message) => {
                const call = activeCall;
                try {
                    await handleMessage(message);
                } catch (error) {
                    if (call && activeCall === call)
                        cleanupCall(error.message || 'Call setup failed.', 'ended', 'failed');
                }
            },
            onDisconnect: () => {
                connected = false;
                cleanupCall('Call service disconnected. Reconnecting...', 'ended', 'failed');
            },
            onError: (error) => {
                if (activeCall) cleanupCall(error.message || 'Call setup failed.', 'ended', 'failed');
                else setStatus(error.message || 'Call service is unavailable.');
            },
        });

        signaling.connect();
        const resumeCalling = () => {
            if (document.hidden) return;
            if (connected) signaling.ensureFresh().catch((error) => setStatus(error.message));
            else signaling.connect();
        };
        document.addEventListener('visibilitychange', resumeCalling);
        window.addEventListener('online', resumeCalling);

        disposeCalling = () => {
            disposed = true;
            removeSoundUnlockListeners();
            if (activeCall?.callUuid) {
                try {
                    signaling.send(
                        activeCall.accepted
                            ? 'call.end'
                            : activeCall.direction === 'outgoing'
                              ? 'call.cancel'
                              : 'call.reject',
                        { call_uuid: activeCall.callUuid },
                    );
                } catch {
                    // Local cleanup must still run after a lost signaling connection.
                }
            }
            cleanupCall();
            callSounds.dispose();
            peerStateTimers.forEach((timer) => window.clearTimeout(timer));
            activeCall = undefined;
            window.clearInterval(timerInterval);
            localStream?.getTracks().forEach((track) => track.stop());
            peerConnection?.close();
            signaling.stop();
            clearInterval(availabilityTimer);
            document.removeEventListener('visibilitychange', resumeCalling);
            window.removeEventListener('online', resumeCalling);
            presence?.leave();
        };
    }
}

document.addEventListener('livewire:navigating', () => {
    disposeCalling();
    mountedApp = undefined;
    disposeCalling = () => {};
});
document.addEventListener('livewire:navigated', initializeCalling);
window.addEventListener('pagehide', () => disposeCalling());
initializeCalling();
