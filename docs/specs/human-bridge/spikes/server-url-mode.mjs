// Spike descartavel: servidor MCP minimo que emite elicitation em mode:"url"
// e fecha com notifications/elicitation/complete. Nao toca estado nenhum.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const log = (...a) => process.stderr.write("[spike] " + a.join(" ") + "\n");

const server = new McpServer(
  { name: "spike-url-elicit", version: "0.0.1" },
  { capabilities: { tools: {} } },
);

const COMPLETE_AFTER_MS = Number(process.env.SPIKE_COMPLETE_AFTER_MS ?? "1500");
const TIMEOUT_MS = Number(process.env.SPIKE_TIMEOUT_MS ?? "20000");

server.registerTool(
  "spike_ask_url",
  {
    title: "spike_ask_url",
    description: "Dispara uma elicitation em mode:url e fecha com notifications/elicitation/complete.",
    inputSchema: { question: z.string() },
  },
  async ({ question }) => {
    const elicitationId = "spike-" + Date.now().toString(36);
    log("capabilities:", JSON.stringify(server.server.getClientCapabilities() ?? null));

    // Agenda o fechamento out-of-band (simula o painel entregando a resposta
    // AO SERVIDOR, que so entao avisa o cliente que a elicitation fechou).
    const t = setTimeout(async () => {
      try {
        await server.server.notification({
          method: "notifications/elicitation/complete",
          params: { elicitationId },
        });
        log("complete-notification: sent", elicitationId);
      } catch (e) {
        log("complete-notification: FAILED", String(e));
      }
    }, COMPLETE_AFTER_MS);

    let out;
    try {
      const r = await server.server.elicitInput(
        {
          mode: "url",
          message: question,
          elicitationId,
          url: "http://127.0.0.1:5173/ask/" + elicitationId,
        },
        { timeout: TIMEOUT_MS },
      );
      out = { kind: "envelope", action: r.action, content: r.content ?? null };
      log("elicitInput RESOLVED:", JSON.stringify(out));
    } catch (e) {
      out = { kind: "throw", name: e?.constructor?.name ?? null, code: e?.code ?? null, message: String(e?.message ?? e) };
      log("elicitInput THREW:", JSON.stringify(out));
    } finally {
      clearTimeout(t);
    }
    return { content: [{ type: "text", text: "SPIKE_RESULT=" + JSON.stringify({ elicitationId, ...out }) }] };
  },
);

await server.connect(new StdioServerTransport());
log("connected");
