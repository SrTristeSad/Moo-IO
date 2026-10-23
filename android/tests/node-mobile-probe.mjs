// Minimal embedded-Node Android smoke test, only used by emulator CI.
import { createServer } from "node:http";
console.log("MOOIO_NODE_PROBE_STARTED");
createServer((_request, response) => {
  response.setHeader("content-type", "application/json");
  response.end(JSON.stringify({ project: "Moo-IO", probe: true }));
}).listen(8081, "127.0.0.1", () => console.log("MOOIO_NODE_PROBE_LISTENING"));
setInterval(() => {}, 60000);
