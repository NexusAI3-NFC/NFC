-- =====================================================================
-- Migración Bloque 2, parte 1: ampliar `tareas` para saber EXACTAMENTE
-- a quién avisar (no vale un texto libre para mandar un push), y crear
-- `push_subscriptions` para guardar las suscripciones de cada socio en
-- cada uno de sus dispositivos.
--
-- Aditivo y seguro de ejecutar ahora — no manda ningún aviso todavía
-- (eso son las Edge Functions, aparte). Pégalo entero en una pestaña
-- nueva del SQL Editor.
-- =====================================================================

-- ---- tareas: título separado, y los ids reales de asignado/creador
alter table public.tareas add column if not exists titulo text;
alter table public.tareas add column if not exists asignado_a_user_id uuid references auth.users(id);
alter table public.tareas add column if not exists creado_por_user_id uuid references auth.users(id);
alter table public.tareas add column if not exists aviso_limite_enviado boolean not null default false;
alter table public.tareas alter column descripcion drop not null;

-- Tareas ya existentes: si no tienen título, usa el principio de la
-- descripción como título para que no queden en blanco en el UI nuevo.
update public.tareas set titulo = descripcion where titulo is null;

-- ---- push_subscriptions: una fila por dispositivo suscrito
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth_key text not null,
  device_label text,
  created_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_id_idx on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists "push: gestionar las propias" on public.push_subscriptions;
create policy "push: gestionar las propias"
  on public.push_subscriptions
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- (Las Edge Functions leerán esta tabla con la service_role key, que
-- se salta el RLS por diseño — no hace falta una política extra para
-- ellas.)
