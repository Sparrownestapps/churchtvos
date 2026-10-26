// Church TV OS MCP server (hosted). Lets an AI assistant (Claude, etc.) work with a church's screens on the person's behalf:
// Signage graphics and runs, Kids playlists and schedules, Slides decks and schedules, live control, and undo.
//
// Sign-in is Supabase Auth's OAuth 2.1 server (the person approves the assistant on app.churchtvos.com/oauth/consent).
// Every database call uses the PERSON'S token, so row-level security applies exactly as it does in the dashboard:
// an assistant can never do more than its user can. Nothing here uses the service-role key.
//
// Transport: MCP "streamable HTTP", stateless, JSON responses only. See README.md for setup and the tool list.
import { createClient } from "npm:@supabase/supabase-js@2";
import { ToolError, type Ctx, type Tool } from "./lib.ts";
import { COMMON_TOOLS } from "./common.ts";
import { SIGNAGE_TOOLS } from "./signage.ts";
import { CONTENT_TOOLS } from "./content.ts";
import { SCHEDULE_TOOLS } from "./schedules.ts";
import { CONTROL_TOOLS } from "./control.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/mcp`;
const SERVER = { name: "church-tv-os", version: "0.2.0" };
const PROTOCOLS = ["2025-06-18", "2025-03-26", "2024-11-05"];

export const TOOLS: Tool[] = [...COMMON_TOOLS, ...SIGNAGE_TOOLS, ...CONTENT_TOOLS, ...SCHEDULE_TOOLS, ...CONTROL_TOOLS];
const BY_NAME = new Map(TOOLS.map((t) => [t.name, t]));

const INSTRUCTIONS = [
  "Church TV OS runs church TVs. Three applications: Signage (graphics/videos on screens by time slot), Kids (playlists of videos, countdowns, lyrics for kids rooms), Slides (decks of text, media, songs, countdowns).",
  "Start with list_targets: it gives the ids and each site's LOCAL date and time. Resolve words like 'Friday' or 'tonight' against that local date, and say the actual date back to the user.",
  "Signage is scheduled on screens (screen_ids); Kids and Slides are scheduled into rooms (location_id). A screen only shows a module while its rules say so; previews warn when they don't (set_screen_module fixes it).",
  "Every tool that changes something returns a PREVIEW first. Show the preview to the user in plain words (what, which screens/rooms, day and date, local times, and any warnings or what it takes over from) and only call again with confirm=true after they say yes. Never confirm on your own.",
  "Images can be sent with upload_image; videos and big files go through request_upload (the user opens a link). Mistakes can be reversed with undo_change.",
].join(" ");

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type, mcp-protocol-version, mcp-session-id, accept",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
  "access-control-expose-headers": "www-authenticate",
};
const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...CORS, ...extra } });

async function handleRpc(msg: any, ctx: Ctx): Promise<unknown | null> {
  const id = msg?.id;
  if (id === undefined) return null; // notification
  const ok = (result: unknown) => ({ jsonrpc: "2.0", id, result });
  switch (msg.method) {
    case "initialize": {
      const asked = msg.params?.protocolVersion;
      return ok({ protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0], capabilities: { tools: { listChanged: false } }, serverInfo: SERVER, instructions: INSTRUCTIONS });
    }
    case "ping": return ok({});
    case "tools/list": return ok({ tools: TOOLS.map(({ run: _run, ...t }) => t) });
    case "tools/call": {
      const tool = BY_NAME.get(msg.params?.name);
      if (!tool) return ok({ isError: true, content: [{ type: "text", text: `Unknown tool: ${msg.params?.name}` }] });
      try {
        const text = await tool.run(ctx, msg.params?.arguments ?? {});
        return ok({ content: [{ type: "text", text }] });
      } catch (e) {
        if (e instanceof ToolError) return ok({ isError: true, content: [{ type: "text", text: e.message }] });
        console.error(tool.name, e);
        return ok({ isError: true, content: [{ type: "text", text: "Something went wrong on the server. If a change was half made, list_activity shows it and undo_change can reverse it." }] });
      }
    }
    default: return { jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${msg.method}` } };
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (url.pathname.includes("/.well-known/oauth-protected-resource")) {
    return json({ resource: FUNCTION_URL, authorization_servers: [`${SUPABASE_URL}/auth/v1`], bearer_methods_supported: ["header"], resource_name: "Church TV OS" });
  }
  if (req.method === "GET") return json({ name: SERVER.name, version: SERVER.version, mcp: FUNCTION_URL });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const unauthorized = () =>
    json({ jsonrpc: "2.0", error: { code: -32001, message: "Sign in required" }, id: null }, 401, {
      "www-authenticate": `Bearer resource_metadata="${FUNCTION_URL}/.well-known/oauth-protected-resource"`,
    });
  const token = /^Bearer (.+)$/i.exec(req.headers.get("authorization") ?? "")?.[1];
  if (!token) return unauthorized();
  const db = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: u, error: ue } = await db.auth.getUser(token);
  if (ue || !u.user) return unauthorized();
  const ctx: Ctx = { db, userId: u.user.id };

  let body: any;
  try { body = await req.json(); } catch { return json({ jsonrpc: "2.0", error: { code: -32700, message: "Parse error" }, id: null }, 400); }
  if (Array.isArray(body)) {
    const results = (await Promise.all(body.map((m) => handleRpc(m, ctx)))).filter((r) => r !== null);
    return results.length ? json(results) : new Response(null, { status: 202, headers: CORS });
  }
  const res = await handleRpc(body, ctx);
  return res === null ? new Response(null, { status: 202, headers: CORS }) : json(res);
});
