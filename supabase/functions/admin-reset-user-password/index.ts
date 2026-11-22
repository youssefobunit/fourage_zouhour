import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.119.0";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

function validPassword(value: unknown): value is string {
  if (typeof value !== "string" || value.length < 12 || value.length > 128) return false;
  if (new TextEncoder().encode(value).length > 72) return false;
  return /[a-z]/.test(value) && /[A-Z]/.test(value) && /[0-9]/.test(value);
}

export default {
  async fetch(req: Request): Promise<Response> {
    if (req.method === "OPTIONS") return new Response("ok", { headers });
    if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authorization = req.headers.get("authorization");
    if (!url || !anonKey || !serviceRoleKey) {
      return reply({ error: "Server configuration error" }, 500);
    }
    if (!authorization?.startsWith("Bearer ")) {
      return reply({ error: "Authentication required" }, 401);
    }

    let body: { userId?: unknown; password?: unknown };
    try {
      const raw = await req.text();
      if (raw.length > 2048) return reply({ error: "Invalid request" }, 400);
      body = JSON.parse(raw);
    } catch (_) {
      return reply({ error: "Invalid request" }, 400);
    }
    const userId = typeof body.userId === "string" ? body.userId : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId) || !validPassword(body.password)) {
      return reply({ error: "Invalid request" }, 400);
    }

    const requesterClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: authData, error: authError } = await requesterClient.auth.getUser();
    if (authError || !authData.user) return reply({ error: "Authentication required" }, 401);

    const admin = createClient(url, serviceRoleKey);
    const { data: requester } = await admin
      .from("profiles")
      .select("role, status")
      .eq("id", authData.user.id)
      .maybeSingle();
    if (requester?.role !== "admin" || requester.status !== "active") {
      return reply({ error: "Administrator permission required" }, 403);
    }

    const { data: permitted, error: limitError } = await admin.rpc(
      "consume_forage_admin_request",
      { p_actor: authData.user.id },
    );
    if (limitError) return reply({ error: "Security configuration required" }, 503);
    if (!permitted) return reply({ error: "Too many requests" }, 429);

    const { error } = await admin.auth.admin.updateUserById(userId, {
      password: body.password,
    });
    if (error) return reply({ error: "Password update failed" }, 400);
    return reply({ ok: true });
  },
};
