// Moo-IO local leaderboard. Only live server-owned state, never user-submitted scores.
// Filter anonymous/shadowed players exactly as the existing points leaderboard.
export const RANK_CATEGORIES = Object.freeze(["gold", "health", "food", "wood", "stone", "kills", "points"]);
export function buildCategoryRanking(players, viewer, category, limit = 10) {
    if (!RANK_CATEGORIES.includes(category)) throw new RangeError("Invalid leaderboard category");
    const value = p => {
        switch (category) {
            case "gold": return p.points;
            case "health": return p.health;
            case "food": return p.food;
            case "wood": return p.wood;
            case "stone": return p.stone;
            case "kills": return p.kills;
            case "points": return p.points;
        }
    };
    return players.filter(p => p.spawned && (!p.shadowed || p === viewer || viewer.role))
        .map(p => ({ player: p, count: Math.max(0, Number(value(p)) || 0) }))
        .sort((a, b) => b.count - a.count || a.player.sid - b.player.sid)
        .slice(0, limit)
        .flatMap(({ player, count }) =>
            [player.sid, player.shownName(viewer), Math.round(count)]);
}
