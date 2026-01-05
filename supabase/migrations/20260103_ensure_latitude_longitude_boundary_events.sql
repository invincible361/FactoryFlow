-- Ensure latitude and longitude columns exist in worker_boundary_events
do $$
begin
    if not exists (
        select 1
        from information_schema.columns
        where table_name = 'worker_boundary_events'
        and column_name = 'latitude'
    ) then
        alter table public.worker_boundary_events add column latitude double precision;
    end if;

    if not exists (
        select 1
        from information_schema.columns
        where table_name = 'worker_boundary_events'
        and column_name = 'longitude'
    ) then
        alter table public.worker_boundary_events add column longitude double precision;
    end if;

    if not exists (
        select 1
        from information_schema.columns
        where table_name = 'worker_boundary_events'
        and column_name = 'type'
    ) then
        alter table public.worker_boundary_events add column type text not null default 'periodic';
    end if;
end $$;
