-- شغّل هذا الملف كاملاً مرة واحدة: Supabase > SQL Editor
create table profiles(id uuid primary key references auth.users on delete cascade,
  role text not null default 'none' check(role in('admin','employee','client','none')),
  name text, username text, created_at timestamptz default now());
create table projects(id uuid primary key default gen_random_uuid(), name text not null, loc text,
  status text default 'plan' check(status in('plan','run','done')), progress int default 0,
  start_date date, due date, price numeric, cover_path text,
  employee_id uuid references profiles(id) on delete set null, employee_name text,
  client_id uuid references profiles(id) on delete set null, client_name text,
  created_at timestamptz default now());
create table entries(id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects on delete cascade,
  kind text not null check(kind in('updates','reports','messages','internal')),
  body text, file_path text, file_type text,
  author_id uuid default auth.uid(), author_name text, created_at timestamptz default now());

create function my_role() returns text language sql security definer stable set search_path=public
as $$ select role from profiles where id=auth.uid() $$;
create function can_see(pid uuid) returns boolean language sql security definer stable set search_path=public
as $$ select exists(select 1 from projects p where p.id=pid and (my_role()='admin' or p.employee_id=auth.uid() or p.client_id=auth.uid())) $$;

alter table profiles enable row level security;
alter table projects enable row level security;
alter table entries enable row level security;

create policy p_sel on profiles for select using(id=auth.uid() or my_role()='admin');
create policy j_sel on projects for select using(my_role()='admin' or employee_id=auth.uid() or client_id=auth.uid());
create policy j_ins on projects for insert with check(my_role()='admin');
create policy j_upd on projects for update using(my_role()='admin' or employee_id=auth.uid());
create policy j_del on projects for delete using(my_role()='admin');
create policy e_sel on entries for select using(can_see(project_id) and (my_role()<>'client' or kind<>'internal'));
create policy e_ins on entries for insert with check(can_see(project_id) and author_id=auth.uid()
  and (my_role() in('admin','employee') or (my_role()='client' and kind='messages')));
create policy e_del on entries for delete using(my_role()='admin');

-- الموظف لا يقدر يغيّر الموظف/العميل/السعر
create function guard_proj() returns trigger language plpgsql security definer set search_path=public as $$
begin if my_role()<>'admin' then
  new.employee_id:=old.employee_id; new.employee_name:=old.employee_name;
  new.client_id:=old.client_id; new.client_name:=old.client_name; new.price:=old.price;
end if; return new; end $$;
create trigger t_guard before update on projects for each row execute function guard_proj();

-- إنشاء حساب (للمدير فقط)
create function create_member(uid uuid,new_role text,nm text,un text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if my_role()<>'admin' then raise exception 'غير مسموح'; end if;
  if new_role not in('employee','client') then raise exception 'دور غير صحيح'; end if;
  insert into profiles(id,role,name,username) values(uid,new_role,nm,un);
end $$;

-- التخزين الخاص للصور والملفات
insert into storage.buckets(id,name,public) values('media','media',false) on conflict do nothing;
create policy m_sel on storage.objects for select to authenticated
  using(bucket_id='media' and can_see(((storage.foldername(name))[1])::uuid));
create policy m_ins on storage.objects for insert to authenticated
  with check(bucket_id='media' and my_role() in('admin','employee') and can_see(((storage.foldername(name))[1])::uuid));
create policy m_del on storage.objects for delete to authenticated using(bucket_id='media' and my_role()='admin');

-- أول مدير: أنشئ مستخدماً من Authentication > Users (مثال: boss@app.example.com) ثم شغّل:
-- insert into profiles(id,role,name,username) select id,'admin','المدير','boss' from auth.users where email='boss@app.example.com';

-- حذف حساب (للمدير فقط)
create function delete_member(uid uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  if my_role()<>'admin' then raise exception 'غير مسموح'; end if;
  if not exists(select 1 from profiles where id=uid and role in('employee','client')) then raise exception 'لا يمكن حذف هذا الحساب'; end if;
  update projects set employee_id=null,employee_name=null where employee_id=uid;
  update projects set client_id=null,client_name=null where client_id=uid;
  delete from auth.users where id=uid;
end $$;

-- ===== من نحن + الخدمات + الورش + جدول الأعمال =====
create table settings(key text primary key, value text);
create table workshops(id uuid primary key default gen_random_uuid(), name text not null, phone text, note text, created_at timestamptz default now());
create table project_workshops(project_id uuid references projects on delete cascade, workshop_id uuid references workshops on delete cascade, primary key(project_id,workshop_id));
create table works(id uuid primary key default gen_random_uuid(), title text not null, phone text, created_at timestamptz default now());
create table service_requests(id uuid primary key default gen_random_uuid(), client_id uuid default auth.uid(), client_name text,
  service text not null, qty numeric, unit text, notes text, phone text, file_path text,
  status text default 'new' check(status in('new','done')), created_at timestamptz default now());
alter table settings enable row level security;
alter table workshops enable row level security;
alter table project_workshops enable row level security;
alter table works enable row level security;
alter table service_requests enable row level security;

create policy s_sel on settings for select to authenticated using(true);
create policy s_ins on settings for insert with check(my_role()='admin');
create policy s_upd on settings for update using(my_role()='admin');
create policy w_all on workshops for all using(my_role()='admin') with check(my_role()='admin');
create policy pw_all on project_workshops for all using(my_role()='admin') with check(my_role()='admin');
create policy k_all on works for all using(my_role()='admin') with check(my_role()='admin');
create policy sr_sel on service_requests for select using(my_role()='admin' or client_id=auth.uid());
create policy sr_ins on service_requests for insert with check(my_role()='client' and client_id=auth.uid() and status='new');
create policy sr_upd on service_requests for update using(my_role()='admin');
create policy sr_del on service_requests for delete using(my_role()='admin');

insert into storage.buckets(id,name,public) values('requests','requests',false) on conflict do nothing;
create policy r_ins on storage.objects for insert to authenticated
  with check(bucket_id='requests' and my_role()='client' and (storage.foldername(name))[1]=auth.uid()::text);
create policy r_sel on storage.objects for select to authenticated
  using(bucket_id='requests' and (my_role()='admin' or (storage.foldername(name))[1]=auth.uid()::text));
create policy r_del on storage.objects for delete to authenticated using(bucket_id='requests' and my_role()='admin');
