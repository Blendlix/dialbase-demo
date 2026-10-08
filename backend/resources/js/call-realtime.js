import echo from './echo.js';

export function joinCallPresence(userId, { onPresence, onPeerState, onConnection, onAvailability }) {
    const members = new Map();
    const channel = echo.join('calls');
    let availability = { ready: false, busy: false };
    let subscribed = false;
    const publishAvailability = () => {
        if (subscribed) channel.whisper('call.availability', { user_id: String(userId), ...availability });
    };
    const heartbeat = setInterval(publishAvailability, 10000);
    const disconnect = () => {
        subscribed = false;
        members.clear();
        publishMembers();
        onConnection?.(false);
    };
    echo.connector.pusher.connection.bind('disconnected', disconnect);
    echo.connector.pusher.connection.bind('unavailable', disconnect);

    const publishMembers = () => onPresence?.([...members.values()]);

    channel
        .here((users) => {
            subscribed = true;
            members.clear();
            users.forEach((user) => members.set(String(user.id), user));
            onConnection?.(true);
            publishMembers();
            publishAvailability();
        })
        .joining((user) => {
            members.set(String(user.id), user);
            publishMembers();
            publishAvailability();
        })
        .leaving((user) => {
            members.delete(String(user.id));
            publishMembers();
        })
        .listenForWhisper('call.ui', (message) => {
            if (String(message.to_id) === String(userId)) {
                onPeerState?.(message);
            }
        })
        .listenForWhisper('call.availability', (message) => {
            if (members.has(String(message.user_id))) onAvailability?.(message);
        })
        .error(disconnect);

    return {
        setAvailability(next) {
            availability = next;
            publishAvailability();
        },
        whisper(peerId, state, details = {}) {
            if (!subscribed) return;
            channel.whisper('call.ui', {
                from_id: String(userId),
                to_id: String(peerId),
                state,
                ...details,
            });
        },
        leave() {
            clearInterval(heartbeat);
            echo.connector.pusher.connection.unbind('disconnected', disconnect);
            echo.connector.pusher.connection.unbind('unavailable', disconnect);
            echo.leave('calls');
        },
    };
}
