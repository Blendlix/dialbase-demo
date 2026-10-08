export function createCallSession({ requestSession, onMessage, onReady, onDisconnect, onError }) {
    let socket;
    let session;
    let sessionRequestedAt;
    let refreshTimer;
    let reconnectTimer;
    let refreshPromise;
    let refreshResolve;
    let refreshReject;
    let refreshTimeout;
    let stopped = false;
    let connecting = false;
    let ready = false;
    let retryDelay = 1000;

    const send = (event, data) => {
        if (!ready || socket?.readyState !== WebSocket.OPEN) {
            throw new Error('Call connection is not ready.');
        }
        const requestId = crypto.randomUUID();
        socket.send(JSON.stringify({ event, request_id: requestId, data }));
        return requestId;
    };

    const scheduleRefresh = () => {
        clearTimeout(refreshTimer);
        const expiresAt = Date.parse(session?.expires_at);
        if (Number.isFinite(expiresAt)) {
            refreshTimer = setTimeout(() => refresh().catch(onError), Math.max(1000, expiresAt - Date.now() - 120000));
        }
    };

    const settleRefresh = (error) => {
        clearTimeout(refreshTimeout);
        if (error) refreshReject?.(error);
        else refreshResolve?.();
        refreshResolve = refreshReject = undefined;
    };

    const reconnect = () => {
        if (stopped || reconnectTimer) return;
        reconnectTimer = setTimeout(() => {
            reconnectTimer = undefined;
            connect();
        }, retryDelay);
        retryDelay = Math.min(retryDelay * 2, 30000);
    };

    const connect = async () => {
        if (stopped || connecting || ready) return;
        if (socket && socket.readyState < 2) return;
        connecting = true;
        try {
            session = await requestSession();
            sessionRequestedAt = Date.now();
            if (stopped) return;
            const current = new WebSocket(session.ws_url, ['jwt', session.token]);
            socket = current;
            const authTimeout = setTimeout(() => current.close(), 15000);
            current.addEventListener('message', async ({ data }) => {
                if (socket !== current || stopped) return;
                try {
                    const message = JSON.parse(data);
                    if (message.event === 'auth.ok') {
                        clearTimeout(authTimeout);
                        ready = true;
                        retryDelay = 1000;
                        onReady(session);
                        scheduleRefresh();
                    } else if (message.event === 'session.refreshed') {
                        session.expires_at = message.data.expires_at;
                        settleRefresh();
                        scheduleRefresh();
                    } else if (message.event === 'session.error') {
                        settleRefresh(new Error(message.error?.message || 'Calling session refresh failed.'));
                        current.close();
                    } else {
                        await onMessage(message);
                    }
                } catch (error) {
                    onError(error);
                }
            });
            current.addEventListener('close', () => {
                clearTimeout(authTimeout);
                if (socket !== current) return;
                ready = false;
                clearTimeout(refreshTimer);
                settleRefresh(new Error('Call service disconnected.'));
                if (!stopped) {
                    onDisconnect();
                    reconnect();
                }
            });
            current.addEventListener('error', () => current.close());
        } catch (error) {
            onError(error);
            reconnect();
        } finally {
            connecting = false;
        }
    };

    const refresh = () => {
        if (refreshPromise) return refreshPromise;
        const current = socket;
        refreshPromise = (async () => {
            const next = await requestSession();
            if (stopped) throw new Error('Calling has stopped.');
            if (socket !== current || !ready) throw new Error('Call service disconnected during refresh.');
            await new Promise((resolve, reject) => {
                refreshResolve = resolve;
                refreshReject = reject;
                refreshTimeout = setTimeout(() => {
                    settleRefresh(new Error('Calling session refresh timed out.'));
                    current?.close();
                }, 10000);
                try {
                    send('session.refresh', { token: next.token });
                    session = next;
                    sessionRequestedAt = Date.now();
                } catch (error) {
                    settleRefresh(error);
                }
            });
        })()
            .catch((error) => {
                if (socket === current) current?.close();
                throw error;
            })
            .finally(() => {
                refreshPromise = undefined;
            });
        return refreshPromise;
    };

    const ensureFresh = async () => {
        if (!ready) throw new Error('Call connection is not ready.');
        const tokenExpiresSoon = Date.parse(session.expires_at) - Date.now() <= 120000;
        const turnExpiresSoon = Date.now() - sessionRequestedAt >= 8 * 60 * 1000;
        if (tokenExpiresSoon || turnExpiresSoon) await refresh();
        return session;
    };

    return {
        connect,
        send,
        ensureFresh,
        getSession: () => session,
        stop() {
            stopped = true;
            ready = false;
            clearTimeout(refreshTimer);
            clearTimeout(reconnectTimer);
            settleRefresh(new Error('Calling has stopped.'));
            socket?.close();
        },
    };
}
