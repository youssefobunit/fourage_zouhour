import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.119.0";
import { readBoundedJson, validateUser } from "./validation.mjs";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

export default {
  async fetch(req: Request): Promise<Response> {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const url = Deno.env.get("SUPABASE_URL");
    const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authorization = req.headers.get("authorization");
    if (!url || !publishableKey || !serviceRoleKey) {
      return json({ error: "Server configuration error" }, 500);
    }
    if (!authorization?.startsWith('Bearer ')) return json({ error: "Authentication required" }, 401);

    const requesterClient = createClient(url, publishableKey, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: authData, error: authError } = await requesterClient.auth.getUser();
    if (authError || !authData.user) return json({ error: "Authentication required" }, 401);

    const admin = createClient(url, serviceRoleKey);
    const { data: requester } = await admin
      .from("profiles")
      .select("role, status")
      .eq("id", authData.user.id)
      .maybeSingle();
    if (requester?.role !== "admin" || requester.status !== "active") {
      return json({ error: "Administrator permission required" }, 403);
    }

    // Durable per-admin limit. A missing migration fails closed.
    const { data: permitted, error: limitError } = await admin.rpc('consume_forage_admin_request', {
      p_actor: authData.user.id,
    });
    if (limitError) return json({ error: 'Security configuration required' }, 503);
    if (!permitted) return json({ error: 'Too many requests' }, 429);

    let details;
    try {
      details = validateUser(await readBoundedJson(req));
    } catch (_) {
      return json({ error: "Invalid request" }, 400);
    }
    const { username, email, fullName, password, role, allowedPages, writablePages } = details;

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName, username },
      app_metadata: { forage_managed: true },
    });
    if (createError || !created.user) {
      return json({ error: "Username is already used or account creation failed" }, 409);
    }

    // Upsert is deliberate: it also works when the profile trigger has not
    // yet been installed, and is safe when that trigger already created it.
    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .upsert({
        id: created.user.id,
        email,
        full_name: fullName,
        username,
        role,
        status: "active",
        allowed_pages: allowedPages,
        writable_pages: writablePages,
        can_export: false,
        updated_at: new Date().toISOString(),
      }, { onConflict: "id" })
      .select()
      .single();
    if (profileError || !profile) {
      await admin.auth.admin.deleteUser(created.user.id);
      return json({ error: "Profile creation failed" }, 500);
    }
    return json({ profile });
  },
};
