-- معرض المشاريع (نافذة "مشاريعنا" في الصفحة الرئيسية)
-- شغّله مرة واحدة: Supabase > SQL Editor
create table showcase(
  id uuid primary key default gen_random_uuid(),
  title text not null, note text, file_path text not null,
  created_at timestamptz default now());
alter table showcase enable row level security;

-- القراءة للجميع (الزوار والمسجّلون) ، والإضافة والحذف للمدير فقط
create policy sc_sel on showcase for select to anon, authenticated using(true);
create policy sc_ins on showcase for insert to authenticated with check(my_role()='admin');
create policy sc_upd on showcase for update to authenticated using(my_role()='admin');
create policy sc_del on showcase for delete to authenticated using(my_role()='admin');

-- تخزين خاص: الزائر يقرأ عبر روابط مؤقتة فقط
insert into storage.buckets(id,name,public) values('showcase','showcase',false) on conflict do nothing;
create policy sc_obj_sel on storage.objects for select to anon, authenticated using(bucket_id='showcase');
create policy sc_obj_ins on storage.objects for insert to authenticated with check(bucket_id='showcase' and my_role()='admin');
create policy sc_obj_del on storage.objects for delete to authenticated using(bucket_id='showcase' and my_role()='admin');
