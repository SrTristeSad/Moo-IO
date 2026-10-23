// Moo-Quest LOCAL COMPATIBILITY CONFIGURATION
//
// The original al007ex/moomoo-clone@06f7c1ca965a7628671676c8d9a7efd3997bb5e7
// imports server/src/anticheat/config.js, but that file is not published in Git.
// This replacement contains only configuration, NEVER the gameplay/AI/server logic.
// Its values are NOT the author's unpublished values. Run on TRUSTED LAN only.
// Native Lua cannot supply official browser bundle seals. Disable ONLY browser-specific
// gates in this local config; other auth, sequence, HMAC, rate limits remain active.
// Do not use this local compatibility policy for an internet-facing server.
export const ANTICHEAT_CONFIG = {
    storage: {
        reports: "reports.jsonl",
        bans: "bans.json"
    },
    connection: {
        maxConnectionsPerIp: 5,
        enforceOrigin: true,
        enforceBuild: true,
        enforceBundle: false, // Native Lua has no browser JS bundle; LAN TEST ONLY.
        requireTicket: true,
        ticketMaxAgeMs: 45000
    },
    seal: {
        mode: 0, // No browser bundle to bind; keyed HMAC + ticket remain enabled.
        mismatchAction: "flag"
    },
    rateLimits: {
        global: [120, 200],
        packets: {
            M: [2, 3],
            D: [50, 70],
            "9": [50, 70],
            e: [6, 10],
            F: [45, 60],
            z: [20, 35],
            H: [12, 20],
            K: [10, 16],
            L: [4, 6],
            N: [4, 6],
            b: [5, 8],
            P: [8, 12],
            Q: [8, 12],
            c: [20, 30],
            "6": [6, 12],
            S: [10, 15],
            "0": [5, 10],
            T: [5, 10],
            R: [8, 12],
            A: [5, 8],
            V: [5, 10],
            I: [5, 8],
            Y: [3, 6]
        },
        strikesToKick: 40,
        strikeDecayMs: 15000,
        anonCooldownMs: 10000
    },
    validation: {
        strikesPerInvalid: 2
    },
    transport: {
        badTag: "close",
        badSequence: "close",
        unknownPacket: "close",
        malformed: "close"
    },
    probes: {
        // The original detection rules were not published.
        // Never fabricate hashes of client source code.
        perRound: 0,
        list: []
    },
    telemetry: {
        required: true,
        firstProbeMs: 30000,
        intervalMs: 60000,
        answerMs: 45000,
        missingAction: "kick",
        flags: {
            2: { name: "SOCKET_HOOKED", action: "kick" },
            16: { name: "SOCKET_INTEGRITY", action: "kick" }
        },
        untrustedEvents: { threshold: 12, action: "flag" },
        ledger: { mismatchAction: "flag" }
    },
    kickLock: {
        anticheatSeconds: 120,
        staffSeconds: 120
    },
    shame: {
        durationMs: 60000
    }
};
