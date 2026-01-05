-- Fix worker_boundary_events table to ensure type column exists
do $$
begin
    if not exists (
        select 1
        from information_schema.columns
        where table_name = 'worker_boundary_events'
        and column_name = 'type'
    ) then
        alter table public.worker_boundary_events add column type text not null default 'periodic';
        -- Remove default after adding if we want it to be mandatory without default later
        alter table public.worker_boundary_events alter column type drop default;
    end if;
end $$;
