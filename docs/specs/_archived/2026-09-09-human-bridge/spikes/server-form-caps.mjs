import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
const server = new McpServer({ name: "spike-url-elicit", version: "0.0.1" }, { capabilities: { tools: {} } });

server.registerTool("spike_probe",
  { title: "spike_probe", description: "Reporta as capabilities do cliente e dispara uma elicitation form-mode.", inputSchema: { question: z.string() } },
  async ({ question }) => {
    const caps = server.server.getClientCapabilities() ?? null;
    let out;
    try {
      const r = await server.server.elicitInput(
        { message: question, requestedSchema: { type: "object", properties: { answer: { type: "string", title: "answer", description: "resposta" } } } },
        { timeout: 20000 },
      );
      out = { kind: "envelope", action: r.action, content: r.content ?? null };
    } catch (e) {
      out = { kind: "throw", code: e?.code ?? null, message: String(e?.message ?? e) };
    }
    return { content: [{ type: "text", text: "SPIKE_CAPS=" + JSON.stringify(caps) + " SPIKE_RESULT=" + JSON.stringify(out) }] };
  });

await server.connect(new StdioServerTransport());
