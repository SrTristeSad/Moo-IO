// SPDX-License-Identifier: AGPL-3.0-only
// Accepted LAN / private VPN IPv4 endpoints. No public Internet hosts.
export function parseIPv4(value) {
    if (typeof value !== "string" || !/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/.test(value)) return null;
    const v=value.split(".").map(Number);
    if (v.some((n,i)=>n>255 || (value.split(".")[i].length>1 && value.split(".")[i][0]==="0"))) return null;
    return v;
}
export function privateNetworkKind(value) {
    const v=parseIPv4(value);
    if (!v) return null;
    const [a,b,c,d]=v;
    if (a===127) return "loopback";
    if (a===10 || (a===172 && b>=16 && b<=31) || (a===192 && b===168)) return "lan";
    if (a===100 && b>=64 && b<=127 && !(b===100 && c===100 && d===100)) return "tailscale";
    // Overlay VPN ranges historically used by Hamachi and Radmin VPN.
    if (a===25 || a===26) return "vpn";
    return null;
}
export function allowedRoomInterface(value,mode) {
    const kind=privateNetworkKind(value);
    if (!kind) return false;
    return mode==="vpn" ? kind!=="loopback" : kind==="lan" || kind==="loopback";
}
