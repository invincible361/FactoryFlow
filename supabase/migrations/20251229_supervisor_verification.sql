-- Add role to workers and verification fields to production_logs

alter table public.workers add column if not exists role text default 'worker';
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'workers_role_chk'
  ) then
    alter table public.workers
      add constraint workers_role_chk
      check (role in ('worker','supervisor'));
  end if;
end $$;

alter table public.production_logs add column if not exists is_verified boolean default false;
alter table public.production_logs add column if not exists verified_by text;
alter table public.production_logs add column if not exists verified_at timestamptz;
alter table public.production_logs add column if not exists verified_note text;
alter table public.production_logs add column if not exists supervisor_quantity integer;
