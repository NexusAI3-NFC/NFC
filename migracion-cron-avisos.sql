-- =====================================================================
-- PASO FINAL del Bloque 2: programa los 2 avisos que no dispara ningún
-- cambio en la base de datos, sino el paso del tiempo.
--
-- ANTES de ejecutar esto:
-- 1. Activa las extensiones pg_cron y pg_net (Database → Extensions).
-- 2. Ten ya desplegada la Edge Function `send-push`.
-- 3. Sustituye <PUSH_SERVICE_KEY> por la clave "service_role" del
--    proyecto (Project Settings → API Keys) — NO la "anon" key. Esta
--    clave es tan sensible como una contraseña de administrador: no la
--    pegues en ningún sitio salvo aquí, el SQL Editor.
-- =====================================================================

select cron.schedule(
  'nexus-recordatorio-fechas-limite',
  '0 * * * *', -- cada hora en punto
  $$
  select net.http_post(
    url := 'https://wrdeltvlwvbssjituhll.supabase.co/functions/v1/smart-processor',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <PUSH_SERVICE_KEY>'
    ),
    body := jsonb_build_object('tipo', 'recordatorio_fechas_limite')
  );
  $$
);

select cron.schedule(
  'nexus-recordatorio-pedidos-pendientes',
  '0 8 * * *', -- una vez al día, 8:00 UTC (cambia la hora si quieres otra distinta)
  $$
  select net.http_post(
    url := 'https://wrdeltvlwvbssjituhll.supabase.co/functions/v1/smart-processor',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <PUSH_SERVICE_KEY>'
    ),
    body := jsonb_build_object('tipo', 'recordatorio_pedidos_pendientes')
  );
  $$
);

-- Comprueba que quedaron programados:
select jobid, jobname, schedule, active from cron.job where jobname like 'nexus-%';
