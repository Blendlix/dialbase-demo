import { test } from 'node:test';
import assert from 'node:assert/strict';
import { acquireCallMedia, matchesCall } from './call-lifecycle.js';

test('late microphone permission releases tracks after cancellation', async () => {
    const call = {};
    let current = call;
    let allowMicrophone;
    let stopped = 0;
    const stream = { getTracks: () => [{ stop: () => stopped++ }] };
    const pending = acquireCallMedia(call, (candidate) => current === candidate, {
        getUserMedia: () =>
            new Promise((resolve) => {
                allowMicrophone = resolve;
            }),
    });
    current = undefined;
    allowMicrophone(stream);
    assert.equal(await pending, null);
    assert.equal(stopped, 1);
});

test('microphone permission for a replaced call cannot affect the new call', async () => {
    const call = {};
    let stopped = false;
    const stream = {
        getTracks: () => [
            {
                stop: () => {
                    stopped = true;
                },
            },
        ],
    };
    assert.equal(await acquireCallMedia(call, () => false, { getUserMedia: async () => stream }), null);
    assert.equal(stopped, true);
});

test('current calls keep their microphone stream', async () => {
    const stream = { getTracks: () => [] };
    assert.equal(await acquireCallMedia({}, () => true, { getUserMedia: async () => stream }), stream);
});

test('late and unidentified events cannot target the active call', () => {
    assert.equal(matchesCall({ callUuid: 'new' }, { call_uuid: 'old' }), false);
    assert.equal(matchesCall(undefined, { call_uuid: 'old' }), false);
    assert.equal(matchesCall({}, {}), false);
    assert.equal(matchesCall({ callUuid: 'new' }, { call_uuid: 'new' }), true);
});
