-- =====================================================================
-- Migración: tabla de tareas pendientes por socio (los TODOs),
-- independiente de las reuniones del calendario.
--
-- (Lo de "nos deben" vs "en mano" no necesita cambios en la base de
-- datos: se calcula solo a partir de si el pedido está entregado o
-- no, así que no hace falta tocar la tabla ventas para eso.)
--
-- Pégalo entero en el SQL Editor de Supabase y ejecútalo de una vez.
-- Es seguro volver a ejecutarlo si algo falla a medias.
-- =====================================================================

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
