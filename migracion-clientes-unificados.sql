-- =====================================================================
-- Migración: unificar clientes de "Vender" (tabla ventas) con la
-- Agenda de clientes (tabla clientes_crm), y limpiar duplicados de
-- productos-servicio creados por una siembra que se ejecutó más de
-- una vez.
--
-- Pégalo entero en el SQL Editor de Supabase y ejecútalo de una vez.
-- Es seguro volver a ejecutarlo si algo falla a medias: los pasos
-- están escritos para no duplicar nada si ya se aplicaron.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Quitar los productos-servicio duplicados (Web / SEO / Redes
--    Sociales aparecían 3 veces cada uno). Nos quedamos con la fila
--    más antigua de cada nombre y borramos el resto.
-- ---------------------------------------------------------------------
with duplicados as (
  select id,
         row_number() over (partition by nombre order by created_at asc) as posicion
  from productos
  where tipo = 'servicio'
)
delete from productos
where id in (select id from duplicados where posicion > 1);

-- Evita que vuelva a pasar si algún día se re-siembra sin comprobar antes.
create unique index if not exists productos_servicio_nombre_unique
  on productos (nombre)
  where tipo = 'servicio';

-- ---------------------------------------------------------------------
-- 2) Enlazar ventas con clientes_crm de verdad (hasta ahora "cliente"
--    en ventas era solo texto suelto, sin relación con la agenda).
-- ---------------------------------------------------------------------
alter table ventas
  add column if not exists cliente_id uuid references clientes_crm(id) on delete set null;

create index if not exists ventas_cliente_id_idx on ventas (cliente_id);

-- Que no se puedan crear dos clientes con el mismo nombre (sin distinguir
-- mayúsculas/espacios) desde ningún sitio a partir de ahora.
create unique index if not exists clientes_crm_nombre_unique_ci
  on clientes_crm (lower(trim(nombre)));

-- ---------------------------------------------------------------------
-- 3) Dar de alta en clientes_crm a todo el que ya os ha comprado algo
--    y todavía no está en la agenda. "Tres sonrisas" (como aparece en
--    ventas) se une al cliente que ya existe como "Clinica tres
--    sonrisas" en vez de crear uno nuevo duplicado.
--
--    Si hay dos variantes de mayúsculas/minúsculas del mismo nombre
--    (p.ej. "Aqui Hay Juegos" y "Aqui hay juegos"), se cuentan como un
--    único cliente y se guarda solo una de las dos formas.
-- ---------------------------------------------------------------------
insert into clientes_crm (nombre)
select dedup.nombre_final
from (
  select distinct on (lower(trim(nombre_final))) nombre_final
  from (
    select
      case
        when lower(trim(cliente)) = 'tres sonrisas' then 'Clinica tres sonrisas'
        else trim(cliente)
      end as nombre_final
    from ventas
    where cliente is not null and trim(cliente) <> ''
  ) normalizados
  order by lower(trim(nombre_final)), nombre_final
) dedup
where not exists (
  select 1 from clientes_crm c
  where lower(trim(c.nombre)) = lower(trim(dedup.nombre_final))
);

-- ---------------------------------------------------------------------
-- 4) Rellenar ventas.cliente_id enlazando por nombre (con la misma
--    normalización de "Tres sonrisas" de arriba).
-- ---------------------------------------------------------------------
update ventas v
set cliente_id = c.id
from clientes_crm c
where v.cliente_id is null
  and lower(trim(c.nombre)) = lower(trim(
        case
          when lower(trim(v.cliente)) = 'tres sonrisas' then 'Clinica tres sonrisas'
          else v.cliente
        end
      ));

-- ---------------------------------------------------------------------
-- Comprobación rápida (opcional): ejecuta esto después para ver que
-- ha quedado todo enlazado. No debería devolver ninguna fila.
-- ---------------------------------------------------------------------
-- select id, cliente from ventas where cliente_id is null;
