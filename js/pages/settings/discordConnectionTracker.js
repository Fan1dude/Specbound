// Wraps the Settings page's Discord connection lookup so:
//
//   1. A slow, older in-flight request can never overwrite a result from
//      a request started after it (Refresh clicked while the initial
//      load is still pending, rapid repeated calls, etc.) — each call to
//      run() gets a monotonically increasing id; a result is only
//      returned if its id still matches the latest call made through
//      this same tracker instance. A superseded call resolves to null,
//      which callers must treat as "discard, a newer call owns the UI
//      now," not as any real connection state.
//   2. A thrown/rejected fetch is reported as its own "error" status,
//      never silently folded into "disconnected" — a network hiccup or
//      RLS/auth timing issue must never be displayed as if the durable
//      social_connections record had confirmed no connection exists.
//
// Deliberately just a request sequencer, not a cache: it holds no
// connection data of its own between calls, so it can never itself hand
// back stale authentication or connection state — every call to run()
// performs a real fetch via the function it was constructed with.
export function createDiscordConnectionTracker(fetchConnection) {
    let latestRequestId = 0;

    async function run() {
        const requestId = ++latestRequestId;

        let connection;

        try {
            connection = await fetchConnection();
        } catch (error) {
            if (requestId !== latestRequestId) return null;
            return { status: "error", error };
        }

        if (requestId !== latestRequestId) return null;

        return connection
            ? { status: "connected", connection }
            : { status: "disconnected" };
    }

    return { run };
}
