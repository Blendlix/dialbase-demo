import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createCallSession } from './call-session.js';

class FakeSocket {
    static OPEN = 1;
    static instances = [];
    readyState = 1;
    listeners = new Map();
    sent = [];

    constructor() {
        FakeSocket.instances.push(this);
    }
    addEventListener(event, listener) {
        this.listeners.set(event, listener);
    }
    send(data) {
        this.sent.push(JSON.parse(data));
    }
    message(message) {
        return this.listeners.get('message')({ data: JSON.stringify(message) });
    }
    close() {
        if (this.readyState === 3) return;
        this.readyState = 3;
        this.listeners.get('close')?.();
    }
}

const session = (token, lifetime = 900000) => ({
    token,
    ws_url: 'wss://rtc.example.test',
    ice_servers: [],
    expires_at: new Date(Date.now() + lifetime).toISOString(),
});

function setup(t, requestSession) {
    FakeSocket.instances = [];
    const originalWebSocket = globalThis.WebSocket;
    globalThis.WebSocket = FakeSocket;
    t.after(() => {
        globalThis.WebSocket = originalWebSocket;
    });
    const client = createCallSession({
        requestSession,
        onMessage: async () => {},
        onReady: () => {},
        onDisconnect: () => {},
        onError: () => {},
    });
    t.after(() => client.stop());
    return client;
}

test('refresh waits for confirmation and supplies fresh ICE configuration', async (t) => {
    let requests = 0;
    const client = setup(t, async () => session(`token-${++requests}`, requests === 1 ? 60000 : 900000));
    await client.connect();
    const socket = FakeSocket.instances[0];
    await socket.message({ event: 'auth.ok' });
    let refreshed = false;
    const pending = client.ensureFresh().then(() => {
        refreshed = true;
    });
    await Promise.resolve();
    assert.equal(socket.sent[0].event, 'session.refresh');
    assert.equal(socket.sent[0].data.token, 'token-2');
    assert.equal(refreshed, false);
    await socket.message({ event: 'session.refreshed', data: { expires_at: session('next').expires_at } });
    await pending;
    assert.equal(refreshed, true);
    assert.equal(client.getSession().token, 'token-2');
});

test('socket loss disables actions and reconnects with a new token', async (t) => {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    let requests = 0;
    const client = setup(t, async () => session(`token-${++requests}`));
    await client.connect();
    await FakeSocket.instances[0].message({ event: 'auth.ok' });
    FakeSocket.instances[0].close();
    assert.throws(() => client.send('call.invite', {}), /not ready/);
    t.mock.timers.tick(1000);
    await Promise.resolve();
    assert.equal(requests, 2);
    assert.equal(FakeSocket.instances.length, 2);
    await FakeSocket.instances[1].message({ event: 'auth.ok' });
    assert.doesNotThrow(() => client.send('call.invite', {}));
});

test('repeated connection requests reuse the socket awaiting authentication', async (t) => {
    const client = setup(t, async () => session('token'));
    await client.connect();
    await client.connect();
    assert.equal(FakeSocket.instances.length, 1);
});

test('refresh rejection closes the session instead of keeping a stale token', async (t) => {
    const client = setup(t, async () => session('token', 60000));
    await client.connect();
    const socket = FakeSocket.instances[0];
    await socket.message({ event: 'auth.ok' });
    const pending = client.ensureFresh();
    await Promise.resolve();
    await socket.message({ event: 'session.error', error: { message: 'Expired token' } });
    await assert.rejects(pending, /Expired token/);
    assert.equal(socket.readyState, 3);
});
