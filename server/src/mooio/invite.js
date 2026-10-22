// SPDX-License-Identifier: AGPL-3.0-only
// Moo IO: invite verification and public protocol parameters for native clients.
import { timingSafeEqual } from "node:crypto";

export const CODE_PATTERN = /^[A-Za-z0-9-]{8,64}$/;

export function validRoomCode(code) {
    return typeof code === "string" && CODE_PATTERN.test(code);
}

export function equalRoomCode(expected, received) {
    if (!validRoomCode(expected) || !validRoomCode(received)) return false;
    const a = Buffer.from(expected, "utf8");
    const b = Buffer.from(received, "utf8");
    return a.length === b.length && timingSafeEqual(a, b);
}

// The JS protocol module delivered to browser clients contains public mixing
// parameters. Never expose secrets such as sealHex, tokens or paths.
export function publicProtocol(raw) {
    if (!raw || typeof raw !== "object") throw new Error("Missing protocol build");
    const {buildId, salt, rounds, tapA, tapB, rotA, rotB, mult, constants} = raw;
    if (!/^[a-z0-9]{1,64}$/.test(buildId || "") || !Array.isArray(constants) ||
        constants.length !== 8 || !constants.every(n => Number.isSafeInteger(n) && n >= 0 && n <= 0xffffffff)) {
        throw new Error("Invalid protocol build");
    }
    const output = {buildId, salt, rounds, tapA, tapB, rotA, rotB, mult, constants};
    for (const field of ["salt","rounds","tapA","tapB","rotA","rotB","mult"]) {
        if (!Number.isSafeInteger(output[field])) throw new Error("Invalid "+field);
    }
    return output;
}

export function requireRoomInvite(code, req, res, next) {
    if (!code) return next();
    if (!equalRoomCode(code, req.get("x-mooio-code") || "")) {
        res.status(403).json({ error: "invite_required" });
        return;
    }
    next();
}
