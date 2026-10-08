import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { acquireCallMedia, matchesCall } from './call-lifecycle.js';
import { createCallWindow } from './call-window.js';

class Element {
    dataset = {};
    children = new Map();
    listeners = new Map();
    classList = { toggle() {} };
    hidden = false;
    disabled = false;
    open = false;
    showModal() {
        this.open = true;
    }
    close() {
        this.open = false;
    }
    focus() {}
    querySelector(selector) {
        if (!this.children.has(selector)) this.children.set(selector, new Element());
        return this.children.get(selector);
    }
    addEventListener(event, listener) {
        this.listeners.set(event, listener);
    }
    setAttribute() {}
    remove() {}
}

async function setup({ blockedAudio = false } = {}) {
    const app = new Element();
    app.dataset = { currentUserId: '1', historyUrl: '/calls/history', sessionUrl: '/calls/session' };
    const button = new Element();
    button.dataset = { callUserId: '2', callUserName: 'Amina' };
    app.querySelectorAll = () => [button];
    let presenceCallbacks;
    let sessionCallbacks;
    let stopped = 0;
    let peerConnection;
    const audioTrack = { enabled: true, stop: () => stopped++ };
    const sent = [];
    const documentListeners = new Map();
    let soundsEnabled = true;
    let soundEnableCalls = 0;
    const playedSounds = [];
    const session = { ice_servers: [], role: 'user', context_type: 'application', context_id: 'test' };
    const signaling = {
        connect() {},
        stop() {},
        send(event, data) {
            const id = `request-${sent.length + 1}`;
            sent.push({ id, event, data });
            return id;
        },
        ensureFresh: async () => session,
        getSession: () => session,
    };
    const window = {
        setTimeout: () => 1,
        clearTimeout() {},
        setInterval: () => 1,
        clearInterval() {},
        addEventListener() {},
        removeEventListener() {},
    };
    const context = {
        window,
        console,
        CSS: { escape: String },
        setInterval: window.setInterval,
        clearInterval: window.clearInterval,
        document: {
            querySelector: () => app,
            addEventListener: (event, listener) => documentListeners.set(event, listener),
            removeEventListener: (event) => documentListeners.delete(event),
        },
        navigator: {
            mediaDevices: {
                getUserMedia: async () => ({
                    getTracks: () => [audioTrack],
                    getAudioTracks: () => [audioTrack],
                }),
            },
        },
        RTCPeerConnection: class {
            constructor() {
                peerConnection = this;
            }
            addTrack() {}
            close() {}
        },
        fetch: async () => ({
            ok: true,
            json: async () => ({
                data: {
                    id: 1,
                    peer_name: 'Amina',
                    direction: 'outgoing',
                    status: 'ringing',
                    initiated_at: new Date().toISOString(),
                    duration_seconds: 0,
                },
            }),
        }),
        joinCallPresence: (_id, callbacks) => {
            presenceCallbacks = callbacks;
            return { whisper() {}, setAvailability() {}, leave() {} };
        },
        createCallSounds: () => ({
            isEnabled: () => soundsEnabled,
            enable() {
                soundsEnabled = true;
                soundEnableCalls++;
                return blockedAudio && soundEnableCalls === 1
                    ? Promise.reject(new Error('Autoplay blocked'))
                    : Promise.resolve();
            },
            play: (type) => {
                if (soundsEnabled) playedSounds.push(type);
            },
            stop() {},
            disable() {
                soundsEnabled = false;
            },
            dispose() {
                soundsEnabled = false;
            },
        }),
        createCallSession: (callbacks) => {
            sessionCallbacks = callbacks;
            return signaling;
        },
        acquireCallMedia,
        matchesCall,
        createCallWindow,
    };
    const source = (await readFile(new URL('./calls.js', import.meta.url), 'utf8'))
        .replace(/^import .*;\n/gm, '')
        .replaceAll('import.meta.env', '({})');
    vm.runInNewContext(source, context);
    sessionCallbacks.onReady(session);

    const available = (busy = false) => {
        presenceCallbacks.onPresence([{ id: '2' }]);
        presenceCallbacks.onAvailability({ user_id: '2', ready: true, busy });
    };
    const invite = async () => {
        available();
        await button.listeners.get('click')();
        return sent.find(({ event }) => event === 'call.invite');
    };
    return {
        app,
        button,
        available,
        invite,
        message: sessionCallbacks.onMessage,
        stopped: () => stopped,
        peer: () => peerConnection,
        audioTrack,
        gesture: (event) => documentListeners.get(event)?.(),
        soundEnableCalls: () => soundEnableCalls,
        playedSounds,
    };
}

test('call controls require presence, signaling readiness and a free peer', async () => {
    const client = await setup();
    assert.equal(client.button.disabled, true);
    client.available();
    assert.equal(client.button.disabled, false);
    client.available(true);
    assert.equal(client.button.disabled, true);
});

test('Dialbase error responses close the panel and release the microphone', async () => {
    const client = await setup();
    const invite = await client.invite();
    await client.message({ event: 'error', request_id: invite.id, error: { message: 'Peer is busy' } });
    assert.equal(client.app.querySelector('[data-call-panel]').hidden, true);
    assert.equal(client.app.querySelector('[data-call-status]').textContent, 'Peer is busy');
    assert.equal(client.stopped(), 1);
});

test('stale terminal events do not close a new call; matching failures do', async () => {
    const client = await setup();
    const invite = await client.invite();
    await client.message({
        event: 'call.invited',
        request_id: invite.id,
        success: true,
        data: { call_uuid: 'current' },
    });
    await client.message({ event: 'call.ended', data: { call_uuid: 'previous' } });
    assert.equal(client.stopped(), 0);
    assert.equal(client.app.querySelector('[data-call-panel]').hidden, false);
    await client.message({ event: 'call.failed', data: { call_uuid: 'current' } });
    assert.equal(client.stopped(), 1);
    assert.equal(client.app.querySelector('[data-call-panel]').hidden, true);
});

test('incoming calls open a modal, then expose timer and mute controls after answering', async () => {
    const client = await setup();
    await client.message({
        event: 'call.ringing',
        data: {
            call_uuid: 'incoming',
            caller_user_id: '2',
            display_name: 'Amina',
        },
    });
    const dialog = client.app.querySelector('[data-call-panel]');
    assert.equal(dialog.open, true);
    assert.equal(dialog.dataset.mode, 'incoming');
    assert.equal(client.app.querySelector('[data-call-peer]').textContent, 'Amina');
    assert.equal(client.app.querySelector('[data-call-accept]').hidden, false);
    await client.app.querySelector('[data-call-accept]').listeners.get('click')();
    assert.equal(dialog.dataset.mode, 'active');
    assert.equal(client.app.querySelector('[data-call-accept]').hidden, true);
    const peer = client.peer();
    peer.connectionState = 'connected';
    peer.onconnectionstatechange();
    assert.equal(client.app.querySelector('[data-call-duration]').hidden, false);
    assert.equal(client.app.querySelector('[data-call-mute]').hidden, false);
    client.app.querySelector('[data-call-mute]').listeners.get('click')();
    assert.equal(client.audioTrack.enabled, false);
    assert.equal(
        client.app.querySelector('[data-call-mute]').querySelector('[data-call-mute-label]').textContent,
        'Unmute',
    );
    client.app.querySelector('[data-call-end]').listeners.get('click')();
    assert.equal(dialog.open, false);
    assert.equal(client.stopped(), 1);
});

test('active calls can be minimized and restored without releasing audio', async () => {
    const client = await setup();
    await client.invite();
    const dialog = client.app.querySelector('[data-call-panel]');
    client.app.querySelector('[data-call-minimize]').listeners.get('click')();
    assert.equal(dialog.open, false);
    assert.equal(client.app.querySelector('[data-call-restore]').hidden, false);
    assert.equal(client.stopped(), 0);
    client.app.querySelector('[data-call-restore]').listeners.get('click')();
    assert.equal(dialog.open, true);
    assert.equal(client.app.querySelector('[data-call-restore]').hidden, true);
});

test('Escape cannot silently dismiss an incoming call', async () => {
    const client = await setup();
    await client.message({
        event: 'call.ringing',
        data: {
            call_uuid: 'incoming',
            caller_user_id: '2',
            display_name: 'Amina',
        },
    });
    const dialog = client.app.querySelector('[data-call-panel]');
    let prevented = false;
    dialog.listeners.get('cancel')({
        preventDefault: () => {
            prevented = true;
        },
    });
    assert.equal(prevented, true);
    assert.equal(dialog.open, true);
    client.app.querySelector('[data-call-reject]').listeners.get('click')();
    assert.equal(dialog.open, false);
});

test('dashboard enables call sounds without an extra button click', async () => {
    const client = await setup();
    assert.equal(client.soundEnableCalls(), 1);
    assert.equal(client.app.querySelector('[data-call-sound-toggle]').textContent, 'Call sounds on');
});

test('a trusted gesture retries blocked audio and starts the pending incoming ringtone', async () => {
    const client = await setup({ blockedAudio: true });
    await client.message({
        event: 'call.ringing',
        data: {
            call_uuid: 'incoming',
            caller_user_id: '2',
            display_name: 'Amina',
        },
    });
    const previouslyPlayed = client.playedSounds.length;
    client.gesture('pointerdown');
    await Promise.resolve();
    assert.equal(client.soundEnableCalls(), 2);
    assert.equal(client.playedSounds.length, previouslyPlayed + 1);
    assert.equal(client.playedSounds.at(-1), 'incoming');
});

test('automatic audio retries respect the users sound toggle', async () => {
    const client = await setup({ blockedAudio: true });
    client.app.querySelector('[data-call-sound-toggle]').listeners.get('click')();
    client.gesture('keydown');
    assert.equal(client.soundEnableCalls(), 1);
    await client.message({
        event: 'call.ringing',
        data: {
            call_uuid: 'incoming',
            caller_user_id: '2',
            display_name: 'Amina',
        },
    });
    assert.equal(client.playedSounds.length, 0);
});
