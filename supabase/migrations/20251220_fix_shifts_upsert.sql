-- Replace ON CONFLICT upsert with conditional inserts to avoid 42P10
insert into public.shifts(name, start_time, end_time)
select 'Morning', '07:30', '19:30'
where not exists (
  select 1 from public.shifts s where s.name = 'Morning'
);

insert into public.shifts(name, start_time, end_time)
select 'Evening', '19:30', '07:30'
where not exists (
  select 1 from public.shifts s where s.name = 'Evening'
);
