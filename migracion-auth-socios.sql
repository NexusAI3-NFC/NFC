-- =====================================================================
-- Migración: tabla `socios`, que une cada cuenta de Supabase Auth con
-- el nombre que se muestra en la app (Ruben, Jesus, Sergio).
--
-- PASO 1 de la migración de login. Esto NO cierra ninguna tabla ni
-- rompe nada de lo que ya funciona — es aditivo y seguro de ejecutar
-- ahora mismo, antes incluso de invitar a nadie.
--
-- Pégalo entero en el SQL Editor de Supabase y ejecútalo de una vez.
-- Es seguro volver a ejecutarlo si algo falla a medias.
-- =====================================================================

create table if not exists socios (
  email text primary key,
  user_id uuid unique references auth.users(id) on delete set null,
  nombre text not null,
  created_at timestamptz not null default now()
);

-- Los 3 socios, identificados por email. `user_id` se queda vacío
-- hasta que cada uno acepte su invitación (lo rellena el trigger de
-- abajo automáticamente, no hace falta tocarlo a mano).
insert into socios (email, nombre) values
  ('ruben.130205@gmail.com', 'Ruben'),
  ('jgonenriquez@gmail.com', 'Jesus'),
  ('sergiofdeez4@gmail.com', 'Sergio')
on conflict (email) do update set nombre = excluded.nombre;

-- Cuando se crea la cuenta de Auth (al aceptar la invitación), esto
-- enlaza automáticamente esa cuenta con su fila en `socios` por email.
create or replace function public.nexus_link_socio_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.socios set user_id = new.id where email = new.email;
  return new;
end;
$$;

drop trigger if exists nexus_on_auth_user_created on auth.users;
create trigger nexus_on_auth_user_created
  after insert on auth.users
  for each row execute function public.nexus_link_socio_on_signup();

-- RLS de la propia tabla `socios`: cualquier usuario CON sesión puede
-- leer la lista completa (para el selector "para quién" de las
-- tareas), pero nadie puede escribir en ella desde el navegador — solo
-- se gestiona desde aquí, el SQL Editor.
alter table socios enable row level security;

drop policy if exists "socios: leer si autenticado" on socios;
create policy "socios: leer si autenticado"
  on socios for select
  using (auth.role() = 'authenticated');

-- (Deliberadamente no hay política de insert/update/delete: por
-- defecto, con RLS activado y sin política para esa operación, queda
-- bloqueada para todo el mundo salvo el propio SQL Editor con tu
-- usuario de administrador.)
