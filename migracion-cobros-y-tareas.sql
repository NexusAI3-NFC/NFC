-- =====================================================================
-- Migración: separar "lo que nos deben" de "lo que ya tenemos en mano"
-- (columna cobrado en ventas), y añadir una tabla de tareas pendientes
-- por socio (los TODOs), aparte del calendario.
--
-- Pégalo entero en el SQL Editor de Supabase y ejecútalo de una vez.
-- Es seguro volver a ejecutarlo si algo falla a medias: los pasos
-- están escritos para no duplicar nada si ya se aplicaron.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Cobros: cada venta sabe si ya se ha cobrado físicamente o si
--    todavía nos lo tienen que pagar.
-- ---------------------------------------------------------------------
alter table ventas
  add column if not exists cobrado boolean not null default false;

alter table ventas
  add column if not exists fecha_cobro date;

-- ---------------------------------------------------------------------
-- 2) Tareas pendientes por socio (los TODOs), independientes de las
--    reuniones del calendario.
-- ---------------------------------------------------------------------
create table if not exists tareas (
  id uuid primary key default gen_random_uuid(),
  descripcion text not null,
  asignado_a text not null,
  hecha boolean not null default false,
  creado_por text,
  created_at timestamptz not null default now(),
  fecha_hecha timestamptz
);

create index if not exists tareas_asignado_a_idx on tareas (asignado_a);
create index if not exists tareas_hecha_idx on tareas (hecha);
