-- Work Assignments and Boundary Events
-- 1. Work Assignments
create table if not exists public.work_assignments (
  id uuid default gen_random_uuid() primary key,
  organization_code text not null references public.organizations(organization_code) on delete cascade,
  worker_id text not null,
  machine_id text not null,
  item_id text not null,
  operation text not null,
  assigned_by text not null,
  status text not null default 'pending',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists work_assignments_worker_id_idx on public.work_assignments(worker_id);
create index if not exists work_assignments_org_code_idx on public.work_assignments(organization_code);

-- 2. Worker Boundary Events
create table if not exists public.worker_boundary_events (
    id uuid default gen_random_uuid() primary key,
    worker_id text not null,
    organization_code text not null references public.organizations(organization_code) on delete cascade,
    type text not null,
    latitude double precision,
    longitude double precision,
    created_at timestamptz default now()
);

create index if not exists worker_boundary_events_worker_id_idx on public.worker_boundary_events(worker_id, created_at desc);
alter table public.worker_boundary_events enable row level security;
drop policy if exists "Enable all for authenticated users" on public.worker_boundary_events;
create policy "Enable all for authenticated users" on public.worker_boundary_events for all using (true) with check (true);

-- 3. Notifications (Duplicate check)
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_code TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type TEXT,
    worker_id TEXT,
    worker_name TEXT,
    read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
