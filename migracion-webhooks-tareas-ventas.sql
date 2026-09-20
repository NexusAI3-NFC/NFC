-- =====================================================================
-- Sustituye a los "Database Webhooks" del Dashboard: 3 triggers que
-- llaman a la Edge Function (lógicamente "send-push") cuando: se crea
-- una tarea, una tarea cambia, o se crea una venta (pedido). Hace
-- justo lo mismo que haría un webhook creado desde la interfaz.
--
-- OJO: la función se desplegó con el slug "smart-processor" (el
-- nombre que se ve en la lista del Dashboard, "send-push", es solo un
-- alias visual — no cambia la URL real). Si alguna vez se despliega
-- de cero con el slug correcto, cambia la URL de abajo.
--
-- Sustituye <PUSH_SERVICE_KEY> por el valor del secret del mismo
-- nombre (Edge Functions → Secrets) — aparece 3 veces. Es tan
-- sensible como una contraseña de administrador: no la pegues en
-- ningún otro sitio ni la subas a git.
-- =====================================================================

-- ---- tareas: INSERT (tarea nueva asignada) ----
create or replace function public.nexus_webhook_tareas_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://wrdeltvlwvbssjituhll.supabase.co/functions/v1/smart-processor',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <PUSH_SERVICE_KEY>'
    ),
    body := jsonb_build_object(
      'type', 'INSERT', 'table', 'tareas', 'schema', 'public',
      'record', to_jsonb(NEW), 'old_record', null
    )
  );
  return NEW;
end;
$$;

drop trigger if exists nexus_tareas_insert_webhook on public.tareas;
create trigger nexus_tareas_insert_webhook
  after insert on public.tareas
  for each row execute function public.nexus_webhook_tareas_insert();

-- ---- tareas: UPDATE (cambia de estado) ----
create or replace function public.nexus_webhook_tareas_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://wrdeltvlwvbssjituhll.supabase.co/functions/v1/smart-processor',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <PUSH_SERVICE_KEY>'
    ),
    body := jsonb_build_object(
      'type', 'UPDATE', 'table', 'tareas', 'schema', 'public',
      'record', to_jsonb(NEW), 'old_record', to_jsonb(OLD)
    )
  );
  return NEW;
end;
$$;

drop trigger if exists nexus_tareas_update_webhook on public.tareas;
create trigger nexus_tareas_update_webhook
  after update on public.tareas
  for each row execute function public.nexus_webhook_tareas_update();

-- ---- ventas: INSERT (pedido nuevo) ----
create or replace function public.nexus_webhook_ventas_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://wrdeltvlwvbssjituhll.supabase.co/functions/v1/smart-processor',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <PUSH_SERVICE_KEY>'
    ),
    body := jsonb_build_object(
      'type', 'INSERT', 'table', 'ventas', 'schema', 'public',
      'record', to_jsonb(NEW), 'old_record', null
    )
  );
  return NEW;
end;
$$;

drop trigger if exists nexus_ventas_insert_webhook on public.ventas;
create trigger nexus_ventas_insert_webhook
  after insert on public.ventas
  for each row execute function public.nexus_webhook_ventas_insert();

-- Comprueba que los 3 triggers quedaron creados:
select event_object_table, trigger_name, event_manipulation
from information_schema.triggers
where trigger_name like 'nexus_%webhook%'
order by event_object_table;
