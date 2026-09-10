// Tool MCP bloqueante comum — sem elicitation, sem hook. So nao retorna.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
const server = new McpServer({ name: "spike-block", version: "0.0.1" }, { capabilities: { tools: {} } });
server.registerTool("spike_block",
  { title: "spike_block", description: "Bloqueia por sleep_ms e retorna.", inputSchema: { sleep_ms: z.number() } },
  async ({ sleep_ms }) => {
    const t0 = Date.now();
    await new Promise((r) => setTimeout(r, sleep_ms));
    return { content: [{ type: "text", text: `SPIKE_BLOCK_DONE after=${Date.now() - t0}ms` }] };
  });
await server.connect(new StdioServerTransport());
