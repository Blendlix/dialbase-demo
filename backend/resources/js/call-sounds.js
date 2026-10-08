export function createCallSounds(paths) {
    const AudioContextConstructor = window.AudioContext || window.webkitAudioContext;
    const oscillators = new Set();

    let audioContext;
    let activeAudio;
    let fallbackInterval;
    let fallbackActive = false;
    let enabled = true;

    const stop = () => {
        window.clearInterval(fallbackInterval);
        fallbackInterval = undefined;
        fallbackActive = false;

        if (activeAudio) {
            activeAudio.pause();
            activeAudio.currentTime = 0;
            activeAudio = undefined;
        }

        oscillators.forEach((oscillator) => {
            try {
                oscillator.stop();
            } catch {
                // The tone may already have finished.
            }
        });
        oscillators.clear();
    };

    const playTone = (frequency, startAt, duration) => {
        if (!audioContext) {
            return;
        }

        const oscillator = audioContext.createOscillator();
        const gain = audioContext.createGain();
        const endAt = startAt + duration;

        oscillator.type = 'sine';
        oscillator.frequency.value = frequency;
        gain.gain.setValueAtTime(0, startAt);
        gain.gain.linearRampToValueAtTime(0.12, startAt + 0.025);
        gain.gain.setValueAtTime(0.12, endAt - 0.04);
        gain.gain.linearRampToValueAtTime(0, endAt);
        oscillator.connect(gain);
        gain.connect(audioContext.destination);
        oscillator.onended = () => oscillators.delete(oscillator);
        oscillators.add(oscillator);
        oscillator.start(startAt);
        oscillator.stop(endAt);
    };

    const playFallbackPattern = (type) => {
        if (!audioContext || !enabled) {
            return;
        }

        const now = audioContext.currentTime;

        if (type === 'outgoing') {
            playTone(440, now, 1.5);
            playTone(480, now, 1.5);
            return;
        }

        playTone(660, now, 0.24);
        playTone(880, now + 0.38, 0.24);
        playTone(660, now + 0.78, 0.32);
    };

    const startFallback = (type) => {
        if (!enabled || fallbackActive) {
            return;
        }

        fallbackActive = true;
        const interval = type === 'outgoing' ? 4000 : 2600;
        playFallbackPattern(type);
        fallbackInterval = window.setInterval(() => playFallbackPattern(type), interval);
    };

    const enable = async () => {
        enabled = true;

        if (!AudioContextConstructor) {
            return;
        }

        audioContext ??= new AudioContextConstructor();

        if (audioContext.state === 'suspended') await audioContext.resume();
    };

    const play = (type) => {
        stop();

        if (!enabled) {
            return;
        }

        const source = paths[type];

        if (!source) {
            startFallback(type);
            return;
        }

        const audio = new Audio(source);
        audio.loop = true;
        audio.volume = 0.65;
        activeAudio = audio;

        const useFallback = () => {
            if (activeAudio !== audio) {
                return;
            }

            activeAudio = undefined;
            audio.pause();
            startFallback(type);
        };

        audio.addEventListener('error', useFallback, { once: true });
        audio.play().catch(useFallback);
    };

    const disable = () => {
        enabled = false;
        stop();
    };

    const dispose = () => {
        disable();
        if (audioContext && audioContext.state !== 'closed') {
            audioContext.close().catch(() => {});
        }
    };

    return {
        enable,
        play,
        stop,
        disable,
        dispose,
        isEnabled: () => enabled,
    };
}
