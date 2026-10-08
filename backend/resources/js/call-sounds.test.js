import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createCallSounds } from './call-sounds.js';

test('sounds default to enabled and their audio context is released on disposal', async (t) => {
    const previousWindow = globalThis.window;
    let audioContext;
    globalThis.window = {
        clearInterval() {},
        AudioContext: class {
            state = 'suspended';
            constructor() {
                audioContext = this;
            }
            async resume() {
                this.state = 'running';
            }
            async close() {
                this.state = 'closed';
            }
        },
    };
    t.after(() => {
        globalThis.window = previousWindow;
    });
    const sounds = createCallSounds({});
    assert.equal(sounds.isEnabled(), true);
    await sounds.enable();
    assert.equal(audioContext.state, 'running');
    sounds.disable();
    assert.equal(sounds.isEnabled(), false);
    await sounds.enable();
    assert.equal(sounds.isEnabled(), true);
    sounds.dispose();
    assert.equal(audioContext.state, 'closed');
});
