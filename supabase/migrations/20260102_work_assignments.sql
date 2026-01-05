-- Create work_assignments table
create table if not exists public.work_assignments (
  id uuid default gen_random_uuid() primary key,
  organization_code text not null references public.organizations(organization_code) on delete cascade,
  worker_id text not null,
  machine_id text not null,
  item_id text not null,
  operation text not null,
  assigned_by text not null, -- Supervisor name
  status text not null default 'pending', -- pending, started, completed, cancelled
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Index for performance
create index if not exists work_assignments_worker_id_idx on public.work_assignments(worker_id);
create index if not exists work_assignments_org_code_idx on public.work_assignments(organization_code);
