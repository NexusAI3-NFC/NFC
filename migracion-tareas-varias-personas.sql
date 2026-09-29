-- =====================================================================
-- Migración: una tarea puede ser para VARIAS personas a la vez (tarea
-- compartida: cuando una la marca como hecha, queda hecha para todas).
--
-- `asignados_user_ids` guarda a quién avisar (push). `asignado_a` pasa
-- a guardar los nombres separados por ", " (p.ej. "Lorena, Claudia")
-- y `asignado_a_user_id` se queda con el primero, por compatibilidad.
--
-- Pégalo entero en el SQL Editor y ejecútalo. Es seguro volver a
-- ejecutarlo.
-- =====================================================================

alter table public.tareas add column if not exists asignados_user_ids uuid[] not null default '{}';

-- Tareas que ya existían: su único asignado pasa a la lista.
update public.tareas
set asignados_user_ids = array[asignado_a_user_id]
where asignado_a_user_id is not null and cardinality(asignados_user_ids) = 0;
