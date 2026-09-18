-- ============================================================
-- Despachos · Sociedad Portuaria Buenaventura
-- Script de instalación en Supabase (SQL Editor)
-- Ejecutar completo, de una sola vez, en un proyecto nuevo o
-- en uno donde estas tablas todavía no existan.
-- ============================================================

-- ---------- 1. Tipos ----------
create type rol_usuario as enum ('super_admin', 'administrativo', 'operativo');
create type estado_traslado as enum ('pendiente', 'en_proceso', 'completado');

-- ---------- 2. Tablas ----------

-- Perfiles: un registro por usuario de auth.users, con su rol.
-- Se crea SOLO (nombre='') y desactivado (activo=false) cuando alguien se registra;
-- el Super Admin le pone nombre, rol y lo activa desde el panel Administrativo.
create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  nombre     text not null default '',
  rol        rol_usuario,
  activo     boolean not null default false,
  created_at timestamptz not null default now()
);

create table traslados (
  id                  uuid primary key default gen_random_uuid(),
  tt                  text not null,
  bl                  text not null,
  producto            text,
  origen              text,
  destino             text,
  cantidad_total      numeric not null check (cantidad_total > 0),
  cantidad_despachada numeric not null default 0 check (cantidad_despachada >= 0),
  estado              estado_traslado not null default 'pendiente',
  created_by          uuid references profiles(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table despachos (
  id           uuid primary key default gen_random_uuid(),
  traslado_id  uuid not null references traslados(id) on delete cascade,
  operador     uuid references profiles(id),
  cantidad     numeric not null check (cantidad > 0),
  created_at   timestamptz not null default now()
);

create index idx_traslados_estado on traslados(estado);
create index idx_despachos_traslado on despachos(traslado_id);
create index idx_despachos_operador on despachos(operador);

-- ---------- 3. Perfil automático al registrarse ----------
-- Cuando alguien hace signUp (por invitación desde el panel Administrativo),
-- se crea su fila en profiles automáticamente, inactiva y sin rol.
create or replace function fn_nuevo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nombre)
  values (new.id, coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1)));
  return new;
end;
$$;

create trigger trg_nuevo_usuario
  after insert on auth.users
  for each row execute function fn_nuevo_usuario();

-- ---------- 4. Reglas de negocio del despacho ----------
-- Antes de insertar: valida que la cantidad no supere lo pendiente
-- (defensa de servidor, aunque el PWA ya valida en el cliente).
create or replace function fn_validar_despacho()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total numeric;
  v_hecho numeric;
begin
  select cantidad_total, cantidad_despachada into v_total, v_hecho
  from traslados where id = new.traslado_id
  for update;

  if not found then
    raise exception 'El traslado no existe.';
  end if;

  if new.cantidad > (v_total - v_hecho) then
    raise exception 'La cantidad (%) supera lo pendiente (%).', new.cantidad, (v_total - v_hecho);
  end if;

  if new.operador is null then
    new.operador := auth.uid();
  end if;

  return new;
end;
$$;

create trigger trg_validar_despacho
  before insert on despachos
  for each row execute function fn_validar_despacho();

-- Después de insertar: acumula la cantidad despachada y recalcula el estado.
create or replace function fn_aplicar_despacho()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update traslados
  set cantidad_despachada = cantidad_despachada + new.cantidad,
      estado = case
                 when cantidad_despachada + new.cantidad >= cantidad_total then 'completado'
                 else 'en_proceso'
               end,
      updated_at = now()
  where id = new.traslado_id;
  return new;
end;
$$;

create trigger trg_aplicar_despacho
  after insert on despachos
  for each row execute function fn_aplicar_despacho();

-- ---------- 5. Helper para políticas (evita recursión en RLS) ----------
create or replace function fn_mi_rol()
returns rol_usuario
language sql
security definer
stable
set search_path = public
as $$
  select rol from profiles where id = auth.uid();
$$;

create or replace function fn_activo()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce((select activo from profiles where id = auth.uid()), false);
$$;

-- ---------- 6. RLS ----------
alter table profiles   enable row level security;
alter table traslados  enable row level security;
alter table despachos  enable row level security;

-- profiles: cada quien ve su propio perfil; Administrativo/Super Admin ven todos.
create policy "ver perfiles" on profiles for select
  using (id = auth.uid() or fn_mi_rol() in ('super_admin', 'administrativo'));

-- profiles: solo Super Admin edita nombre/rol/activo de cualquiera.
create policy "super admin edita perfiles" on profiles for update
  using (fn_mi_rol() = 'super_admin')
  with check (fn_mi_rol() = 'super_admin');

create policy "super admin elimina perfiles" on profiles for delete
  using (fn_mi_rol() = 'super_admin');

-- traslados: cualquier usuario activo (los 3 roles) puede verlos.
create policy "ver traslados" on traslados for select
  using (fn_activo());

-- traslados: solo Administrativo/Super Admin los crean, editan o eliminan.
create policy "administrativo gestiona traslados" on traslados for all
  using (fn_mi_rol() in ('administrativo', 'super_admin'))
  with check (fn_mi_rol() in ('administrativo', 'super_admin'));

-- despachos: Operativo ve los suyos; Administrativo/Super Admin ven todos.
create policy "ver despachos" on despachos for select
  using (operador = auth.uid() or fn_mi_rol() in ('administrativo', 'super_admin'));

-- despachos: solo Operativo (activo) puede registrar.
create policy "operativo registra despachos" on despachos for insert
  with check (fn_mi_rol() = 'operativo' and fn_activo());

-- ============================================================
-- Fin del script.
-- Después de ejecutarlo, crea manualmente el primer Super Admin:
--   1) En Authentication > Users, invita o crea tu propio usuario.
--   2) En Table editor > profiles, edita esa fila: pon tu nombre,
--      rol = 'super_admin' y activo = true.
-- Desde ahí, ya puedes crear a los demás desde el panel Administrativo.
-- ============================================================
