begin;
select set_config('app.test.actor',gen_random_uuid()::text,true);
select set_config('app.test.other',gen_random_uuid()::text,true);
select set_config('app.test.publication',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) values
(current_setting('app.test.actor')::uuid,'authenticated','authenticated','crud-author@example.invalid','{"alias":"Prueba CRUD"}',now(),now()),
(current_setting('app.test.other')::uuid,'authenticated','authenticated','crud-other@example.invalid','{"alias":"Prueba permisos"}',now(),now());
insert into public.publications(id,client_mutation_id,author_id,kind,category,title,description,district_ubigeo,approx_lat,approx_lng)
values(current_setting('app.test.publication')::uuid,gen_random_uuid(),current_setting('app.test.actor')::uuid,'anuncio','general','Aviso de prueba','Prueba transaccional','150110',-12.076,-77.063);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('app.test.actor'),true);
do $$ declare v integer; result integer; blocked boolean:=false; payload jsonb:='{"title":"Aviso editado","description":"Contenido corregido","category":"general","availability_text":""}'; begin
 select version into v from public.publications where id=current_setting('app.test.publication')::uuid;
 result:=public.mutate_publication(current_setting('app.test.publication')::uuid,v,'edit-crud',false,payload);
 if result<>v+1 then raise exception 'No incrementó versión';end if;
 if public.mutate_publication(current_setting('app.test.publication')::uuid,v,'edit-crud',false,payload)<>result then raise exception 'Reintento no idempotente';end if;
 begin perform public.mutate_publication(current_setting('app.test.publication')::uuid,v,'stale-crud',false,payload);exception when sqlstate 'PT409' then blocked:=true;end;
 if not blocked then raise exception 'Se aceptó versión antigua';end if;
 if not exists(select 1 from public.neighborhood_feed('150110',null,null,30) where publication->>'id'=current_setting('app.test.publication')) then raise exception 'No aparece en feed';end if;
 result:=public.mutate_publication(current_setting('app.test.publication')::uuid,result,'delete-crud',true,'{}');
 if public.mutate_publication(current_setting('app.test.publication')::uuid,v+1,'delete-crud',true,'{}')<>result then raise exception 'Eliminación no idempotente';end if;
 if exists(select 1 from public.neighborhood_feed('150110',null,null,30) where publication->>'id'=current_setting('app.test.publication')) then raise exception 'El feed expone eliminado';end if;
 if not exists(select 1 from public.publication_tombstones where publication_id=current_setting('app.test.publication')::uuid) then raise exception 'No se propagará la eliminación';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('app.test.other'),true);
do $$ declare blocked boolean:=false;begin
 if exists(select 1 from public.publications where id=current_setting('app.test.publication')::uuid) then raise exception 'Otro usuario ve contenido eliminado';end if;
 begin perform public.mutate_publication(current_setting('app.test.publication')::uuid,1,'forbidden',true,'{}');exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Otro usuario modificó el aviso';end if;
end $$;
reset role;
set local role anon;
do $$ declare blocked boolean:=false;begin
 begin perform public.neighborhood_feed(null,null,null,30);exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Feed anónimo';end if;
end $$;
reset role;
rollback;
select 'CRUD, feed, versiones, reintentos, tombstones y permisos verificados; datos de prueba revertidos' as resultado;
