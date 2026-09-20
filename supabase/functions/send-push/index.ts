// =====================================================================
// NEXUS · Edge Function `send-push`
//
// La llaman 3 Database Webhooks (INSERT/UPDATE en `tareas`, INSERT en
// `ventas`) y 2 tareas de pg_cron (recordatorios por tiempo). Decide a
// quién avisar según lo que le llegue, y manda el push de verdad con
// web-push, usando las claves VAPID guardadas como secrets.
//
// No la ejecuta el navegador — corre en el servidor de Supabase, así
// que usa la service_role key (se salta el RLS a propósito, es de
// confianza).
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
// Ojo: NO se usa la variable SUPABASE_SERVICE_ROLE_KEY que inyecta
// Supabase automáticamente — en proyectos con el sistema de claves
// nuevo puede no coincidir con la "secret key" (sb_secret_...) que se
// ve en Project Settings. Se usa un secret propio, PUSH_SERVICE_KEY,
// para tener control total sobre qué valor es y que coincida siempre
// con lo que se pega en el SQL de los triggers/cron.
const SERVICE_ROLE_KEY = Deno.env.get("PUSH_SERVICE_KEY")!;
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;

webpush.setVapidDetails("mailto:ruben.130205@gmail.com", VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

async function enviarATodos(userIds: string[], payload: Record<string, unknown>) {
  const idsUnicos = [...new Set(userIds.filter(Boolean))];
  if (!idsUnicos.length) return;

  const { data: subs } = await sb.from("push_subscriptions").select("*").in("user_id", idsUnicos);

  await Promise.all((subs || []).map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } },
        JSON.stringify(payload),
      );
    } catch (err) {
      const status = (err as { statusCode?: number })?.statusCode;
      if (status === 404 || status === 410) {
        // La suscripción ya no existe (se desinstaló la app, se borraron
        // datos del navegador...) — se limpia sola.
        await sb.from("push_subscriptions").delete().eq("id", s.id);
      } else {
        console.error("Error mandando push a", s.endpoint, err);
      }
    }
  }));
}

async function idsDeTodosLosSocios(): Promise<string[]> {
  const { data } = await sb.from("socios").select("user_id").not("user_id", "is", null);
  return (data || []).map((s) => s.user_id as string);
}

Deno.serve(async (req) => {
  // Comprobación propia de la clave: el proyecto usa el sistema de
  // claves nuevo de Supabase (sb_secret_...), que no es un JWT, así
  // que la verificación automática de JWT de la plataforma no vale
  // aquí — se compara a mano contra PUSH_SERVICE_KEY (ver Secrets).
  const auth = req.headers.get("Authorization") || "";
  const esperado = `Bearer ${SERVICE_ROLE_KEY}`;
  if (auth !== esperado) {
    // No imprime la clave entera, solo longitudes y los últimos 6
    // caracteres de cada una — útil si algún día se rota la clave y
    // deja de encajar, sin exponer el secreto en los logs.
    console.error("NO AUTORIZADO — diagnóstico:", {
      recibido_len: auth.length,
      esperado_len: esperado.length,
      recibido_final: auth.slice(-6),
      esperado_final: esperado.slice(-6),
      secret_key_presente: !!SERVICE_ROLE_KEY,
      secret_key_len: (SERVICE_ROLE_KEY || "").length,
    });
    return new Response(JSON.stringify({ ok: false, error: "No autorizado" }), { status: 401 });
  }

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ ok: false, error: "JSON inválido" }), { status: 400 });
  }

  try {
    // ---- Database Webhook: nueva tarea asignada ----
    if (payload.table === "tareas" && payload.type === "INSERT") {
      const t = payload.record;
      if (t.asignado_a_user_id) {
        await enviarATodos([t.asignado_a_user_id], {
          title: "Tarea nueva",
          body: t.titulo || t.descripcion || "Tienes una tarea nueva",
          url: "./index.html",
        });
      }
    }

    // ---- Database Webhook: tarea cambia de estado ----
    else if (payload.table === "tareas" && payload.type === "UPDATE") {
      const t = payload.record;
      const anterior = payload.old_record || {};
      const pasoAHecha = !anterior.hecha && t.hecha;
      const pasoAEnProgreso = anterior.estado !== "en_progreso" && t.estado === "en_progreso";
      if ((pasoAHecha || pasoAEnProgreso) && t.creado_por_user_id) {
        await enviarATodos([t.creado_por_user_id], {
          title: pasoAHecha ? "Tarea completada" : "Tarea en progreso",
          body: `${t.titulo || t.descripcion || "Una tarea"}${t.asignado_a ? " — " + t.asignado_a : ""}`,
          url: "./index.html",
        });
      }
    }

    // ---- Database Webhook: pedido nuevo de un cliente ----
    else if (payload.table === "ventas" && payload.type === "INSERT") {
      const v = payload.record;
      if (v.origen === "cliente") {
        const ids = await idsDeTodosLosSocios();
        await enviarATodos(ids, {
          title: "Pedido nuevo",
          body: `${v.cliente || "Un cliente"} ha hecho un pedido`,
          url: "./index.html",
        });
      }
    }

    // ---- pg_cron: fechas límite de tareas que se acercan ----
    else if (payload.tipo === "recordatorio_fechas_limite") {
      const manana = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
      const { data: tareas } = await sb
        .from("tareas")
        .select("*")
        .eq("hecha", false)
        .eq("aviso_limite_enviado", false)
        .not("fecha_limite", "is", null)
        .lte("fecha_limite", manana);

      for (const t of tareas || []) {
        if (t.asignado_a_user_id) {
          await enviarATodos([t.asignado_a_user_id], {
            title: "Fecha límite cerca",
            body: `${t.titulo || t.descripcion || "Una tarea"} — límite ${t.fecha_limite}`,
            url: "./index.html",
          });
        }
        await sb.from("tareas").update({ aviso_limite_enviado: true }).eq("id", t.id);
      }
    }

    // ---- pg_cron: pedidos pendientes acumulados ----
    else if (payload.tipo === "recordatorio_pedidos_pendientes") {
      const { count } = await sb
        .from("ventas")
        .select("id", { count: "exact", head: true })
        .eq("entregado", false)
        .eq("origen", "cliente");
      if (count && count > 0) {
        const ids = await idsDeTodosLosSocios();
        await enviarATodos(ids, {
          title: "Pedidos pendientes",
          body: `Hay ${count} pedido${count === 1 ? "" : "s"} sin entregar`,
          url: "./index.html",
        });
      }
    }

    return new Response(JSON.stringify({ ok: true }), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    console.error("send-push error:", err);
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
