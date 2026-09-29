-- =====================================================================
-- Migración: departamentos (Dirección / Marketing).
--
-- 1. `socios.departamento`: los 3 socios son 'direccion'; Lorena y
--    Claudia entran como 'marketing'.
-- 2. `reuniones.departamento` y `tareas.departamento`: para pintar el
--    calendario por colores. Todo lo que ya existe queda como
--    'direccion'.
-- 3. RLS: las tablas de dinero (compras, gastos_generales, ahorros,
--    tarifas_redes_sociales) pasan de "cualquiera con sesión" a "solo
--    Dirección". Marketing sigue pudiendo usar clientes_crm, reuniones
--    y tareas (lo que necesita la Agenda).
--
-- Después de ejecutar esto, invita a las dos desde Authentication →
-- Users → Invite user. Al aceptar, el trigger que ya existe enlaza su
-- cuenta con su fila de `socios` por email.
--
-- Pégalo entero en el SQL Editor y ejecútalo de una vez. Es seguro
-- volver a ejecutarlo.
-- =====================================================================

-- ---- 1) socios.departamento
alter table public.socios add column if not exists departamento text not null default 'direccion';
alter table public.socios drop constraint if exists socios_departamento_check;
alter table public.socios add constraint socios_departamento_check
  check (departamento in ('direccion', 'marketing'));

insert into public.socios (email, nombre, departamento) values
  ('24lorenatt@gmail.com', 'Lorena', 'marketing'),
  ('claudiaenajas2005@gmail.com', 'Claudia', 'marketing')
on conflict (email) do update set nombre = excluded.nombre, departamento = excluded.departamento;

-- Por si ya tenían cuenta de Auth creada antes de estar en `socios`.
update public.socios s set user_id = u.id
from auth.users u
where s.user_id is null and lower(u.email) = lower(s.email);

-- ---- 2) departamento en reuniones y tareas
alter table public.reuniones add column if not exists departamento text not null default 'direccion';
alter table public.reuniones drop constraint if exists reuniones_departamento_check;
alter table public.reuniones add constraint reuniones_departamento_check
  check (departamento in ('direccion', 'marketing'));

alter table public.tareas add column if not exists departamento text not null default 'direccion';
alter table public.tareas drop constraint if exists tareas_departamento_check;
alter table public.tareas add constraint tareas_departamento_check
  check (departamento in ('direccion', 'marketing'));

-- ---- 3) ¿El usuario con sesión es de Dirección?
-- security definer para poder leer `socios` desde dentro de una
-- política sin depender del RLS de la propia tabla.
create or replace function public.es_direccion()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.socios
    where user_id = auth.uid() and departamento = 'direccion'
  );
$$;

-- Tablas de dinero: se borra cualquier política que tuvieran (nombres
-- puestos a mano en su día) y se deja una sola, "solo Dirección".
-- OJO: ventas y productos NO se tocan — catalogo.html y
-- seguimiento-cliente.html dependen de su acceso anónimo.
do $$
declare
  t text;
  p record;
begin
  foreach t in array array['compras', 'gastos_generales', 'ahorros', 'tarifas_redes_sociales'] loop
    execute format('alter table public.%I enable row level security', t);
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format(
      'create policy "solo direccion" on public.%I for all using (public.es_direccion()) with check (public.es_direccion())',
      t
    );
  end loop;
end $$;

-- Las vistas internas se ejecutan por defecto con los permisos de su
-- dueño (se saltan el RLS). Con security_invoker aplican el RLS de
-- quien las consulta, así Marketing no ve compras/gastos a través de
-- ellas.
alter view if exists public.resumen_global set (security_invoker = true);
alter view if exists public.resumen_stock set (security_invoker = true);
alter view if exists public.pedidos_pendientes set (security_invoker = true);

-- ---------------------------------------------------------------------
-- Comprobación (opcional):
-- select email, nombre, departamento, user_id from socios order by departamento, nombre;
-- select tablename, policyname from pg_policies where schemaname = 'public' order by tablename;
-- ---------------------------------------------------------------------
