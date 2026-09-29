-- =====================================================================
-- Migración: avisos push de REUNIONES.
--
-- 1. Reunión nueva → aviso a las personas de su departamento, o a todo
--    el mundo si es "para todos" (lo elige quien la crea). A quien la
--    crea no se le avisa.
-- 2. Las reuniones pueden ser de departamento 'todos'.
-- 3. Cada mañana (9:00 hora española en verano, 8:00 en invierno) →
--    recordatorio con las reuniones de hoy a cada departamento.
--
-- La clave PUSH_SERVICE_KEY NO hay que pegarla: se copia sola del
-- trigger de tareas que ya existe (nexus_webhook_tareas_insert).
--
-- Pégalo entero en el SQL Editor y ejecútalo. Es seguro volver a
-- ejecutarlo.
-- =====================================================================

-- Reuniones "para todos".
alter table public.reuniones drop constraint if exists reuniones_departamento_check;
alter table public.reuniones add constraint reuniones_departamento_check
  check (departamento in ('direccion', 'marketing', 'todos'));

-- Quién creó la reunión, para no avisarle de la suya propia.
alter table public.reuniones add column if not exists creado_por_user_id uuid references auth.users(id);

do $$
declare
  clave text;
  url constant text := 'https://wrdeltvlwvbssjituhll.supabase.co/functions/v1/smart-processor';
begin
  select substring(prosrc from 'Bearer ([^'']+)''') into clave
  from pg_proc where proname = 'nexus_webhook_tareas_insert';
  if clave is null or clave like '<%' then
    raise exception 'No encuentro la PUSH_SERVICE_KEY en nexus_webhook_tareas_insert';
  end if;

  -- ---- 1) Trigger: reunión nueva
  execute format($f$
    create or replace function public.nexus_webhook_reuniones_insert()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
    as $body$
    begin
      perform net.http_post(
        url := %L,
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', %L),
        body := jsonb_build_object(
          'type', 'INSERT', 'table', 'reuniones', 'schema', 'public',
          'record', to_jsonb(NEW), 'old_record', null
        )
      );
      return NEW;
    end;
    $body$;
  $f$, url, 'Bearer ' || clave);

  -- ---- 2) Cron: reuniones de hoy, cada mañana a las 7:00 UTC
  perform cron.unschedule(jobid) from cron.job where jobname = 'nexus-recordatorio-reuniones-hoy';
  perform cron.schedule(
    'nexus-recordatorio-reuniones-hoy',
    '0 7 * * *',
    format($c$
      select net.http_post(
        url := %L,
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', %L),
        body := jsonb_build_object('tipo', 'recordatorio_reuniones_hoy')
      );
    $c$, url, 'Bearer ' || clave)
  );
end $$;

drop trigger if exists nexus_reuniones_insert_webhook on public.reuniones;
create trigger nexus_reuniones_insert_webhook
  after insert on public.reuniones
  for each row execute function public.nexus_webhook_reuniones_insert();

-- ---------------------------------------------------------------------
-- Comprobación (opcional):
-- select jobname, schedule, active from cron.job where jobname like 'nexus-%';
-- ---------------------------------------------------------------------
