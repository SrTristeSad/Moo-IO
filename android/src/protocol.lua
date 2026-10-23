-- Explicitly unimplemented. Packet IDs, codec and handshake must be
-- determined from permitted server/shared sources and validated against a live server.
local Protocol={}
function Protocol.implementedCount() return 0 end
return Protocol
