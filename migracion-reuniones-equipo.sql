-- =====================================================================
-- Migración: reuniones de equipo (sin cliente).
--
-- `cliente_id` pasa a ser opcional y se añade `titulo` para poner
-- nombre a la reunión interna (p.ej. "Planificación semanal").
--
-- Pégalo entero en el SQL Editor y ejecútalo. Es seguro volver a
-- ejecutarlo.
-- =====================================================================

alter table public.reuniones alter column cliente_id drop not null;
alter table public.reuniones add column if not exists titulo text;
