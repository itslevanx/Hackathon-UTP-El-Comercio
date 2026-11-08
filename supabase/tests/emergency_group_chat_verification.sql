begin;
select set_config('test.group.author',gen_random_uuid()::text,true);
select set_config('test.group.neighbor',gen_random_uuid()::text,true);
select set_config('test.group.reader',gen_random_uuid()::text,true);
select set_config('test.group.outsider',gen_random_uuid()::text,true);
select set_config('test.group.publication',gen_random_uuid()::text,true);
select set_config('test.group.private',gen_random_uuid()::text,true);
select set_config('test.group.message',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at)
select current_setting('test.group.'||name)::uuid,'authenticated','authenticated',name||'@group-test.example.invalid',jsonb_build_object('alias','Prueba '||name),now(),now()
from unnest(array['author','neighbor','reader','outsider']) name;
update public.profiles set district_ubigeo='150110' where id in
(current_setting('test.group.author')::uuid,current_setting('test.group.neighbor')::uuid,current_setting('test.group.reader')::uuid);
update public.profiles set district_ubigeo='150101' where id=current_setting('test.group.outsider')::uuid;
insert into public.publications(id,client_mutation_id,author_id,kind,category,title,description,district_ubigeo,approx_lat,approx_lng)
values(current_setting('test.group.publication')::uuid,gen_random_uuid(),current_setting('test.group.author')::uuid,'emergencia_solicitud','general','Emergencia de prueba','Prueba transaccional','150110',-12.076,-77.063);
insert into public.conversations(id,client_mutation_id,publication_id,publication_author_id,participant_id)
values(current_setting('test.group.private')::uuid,gen_random_uuid(),current_setting('test.group.publication')::uuid,current_setting('test.group.author')::uuid,current_setting('test.group.neighbor')::uuid);
insert into public.messages(id,client_mutation_id,conversation_id,sender_id,body)
values(gen_random_uuid(),gen_random_uuid(),current_setting('test.group.private')::uuid,current_setting('test.group.author')::uuid,'Contenido privado que no debe aparecer en el grupo');
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.group.author'),true);
do $$ declare v_message_id uuid:=current_setting('test.group.message')::uuid; blocked boolean:=false;begin
 if public.send_emergency_group_message(v_message_id,v_message_id,current_setting('test.group.publication')::uuid,'Mensaje público de prueba')<>v_message_id then raise exception 'No envió';end if;
 if public.send_emergency_group_message(v_message_id,v_message_id,current_setting('test.group.publication')::uuid,'Mensaje público de prueba')<>v_message_id then raise exception 'Reintento no idempotente';end if;
 if (select count(*) from public.emergency_group_messages where client_mutation_id=v_message_id)<>1 then raise exception 'Mensaje duplicado';end if;
 begin insert into public.emergency_group_messages(id,client_mutation_id,publication_id,sender_id,body)
 values(gen_random_uuid(),gen_random_uuid(),current_setting('test.group.publication')::uuid,current_setting('test.group.neighbor')::uuid,'Suplantación');
 exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Se permitió suplantar al remitente';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.group.neighbor'),true);
select public.send_emergency_group_message(gen_random_uuid(),gen_random_uuid(),current_setting('test.group.publication')::uuid,'Respuesta del vecino');
select set_config('request.jwt.claim.sub',current_setting('test.group.reader'),true);
do $$ begin
 if (select count(*) from public.list_emergency_group_messages(current_setting('test.group.publication')::uuid))<>2 then raise exception 'Vecino no puede ver el grupo';end if;
 if exists(select 1 from public.messages where conversation_id=current_setting('test.group.private')::uuid) then raise exception 'El grupo expone un chat privado';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.group.outsider'),true);
do $$ declare blocked boolean:=false;begin
 if exists(select 1 from public.list_emergency_group_messages(current_setting('test.group.publication')::uuid)) then raise exception 'Otro distrito leyó mensajes';end if;
 begin perform public.send_emergency_group_message(gen_random_uuid(),gen_random_uuid(),current_setting('test.group.publication')::uuid,'No permitido');exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Otro distrito escribió';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.group.author'),true);
update public.publications set status='resuelta' where id=current_setting('test.group.publication')::uuid;
do $$ declare blocked boolean:=false;begin
 if (select count(*) from public.list_emergency_group_messages(current_setting('test.group.publication')::uuid))<>2 then raise exception 'Se perdió el historial cerrado';end if;
 begin perform public.send_emergency_group_message(gen_random_uuid(),gen_random_uuid(),current_setting('test.group.publication')::uuid,'Mensaje en emergencia cerrada');exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Se escribió en grupo cerrado';end if;
end $$;
reset role;
set local role anon;
do $$ declare blocked boolean:=false;begin
 begin perform public.list_emergency_group_messages(current_setting('test.group.publication')::uuid);exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Lectura anónima permitida';end if;
end $$;
reset role;
rollback;
select 'Chat grupal, aislamiento por distrito, chat privado, idempotencia y cierre verificados; pruebas revertidas' as resultado;
