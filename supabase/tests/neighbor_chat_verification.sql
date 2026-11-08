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

select set_config('test.neighbor.publication',gen_random_uuid()::text,true);
select set_config('test.neighbor.reverse_publication',gen_random_uuid()::text,true);
select set_config('test.neighbor.legacy_chat',gen_random_uuid()::text,true);
select set_config('test.neighbor.message',gen_random_uuid()::text,true);
insert into public.publications(id,client_mutation_id,author_id,kind,category,title,description,district_ubigeo)
values(current_setting('test.neighbor.publication')::uuid,gen_random_uuid(),current_setting('test.group.author')::uuid,'servicio','electricidad','Segundo servicio','Contexto de prueba','150110'),
(current_setting('test.neighbor.reverse_publication')::uuid,gen_random_uuid(),current_setting('test.group.neighbor')::uuid,'servicio','general','Servicio del otro vecino','Contexto inverso','150110');
insert into public.conversations(id,client_mutation_id,publication_id,publication_author_id,participant_id)
values(current_setting('test.neighbor.legacy_chat')::uuid,gen_random_uuid(),current_setting('test.neighbor.publication')::uuid,current_setting('test.group.author')::uuid,current_setting('test.group.neighbor')::uuid);
insert into public.messages(id,client_mutation_id,conversation_id,sender_id,body)
values(gen_random_uuid(),gen_random_uuid(),current_setting('test.neighbor.legacy_chat')::uuid,current_setting('test.group.neighbor')::uuid,'Mensaje histórico de otro servicio');
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

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.group.neighbor'),true);
do $$ declare selected uuid; begin
 selected:=public.ensure_neighbor_conversation(gen_random_uuid(),gen_random_uuid(),current_setting('test.neighbor.publication')::uuid);
 if selected not in (current_setting('test.group.private')::uuid,current_setting('test.neighbor.legacy_chat')::uuid) then raise exception 'No reutilizó el chat existente';end if;
 if (select count(*) from public.conversations)<>2 then raise exception 'Creó un tercer chat';end if;
 if (select count(*) from public.list_neighbor_messages(current_setting('test.group.author')::uuid))<>2 then raise exception 'Se perdió historial de servicios anteriores';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.group.author'),true);
do $$ declare sent jsonb; begin
 perform public.ensure_neighbor_conversation(gen_random_uuid(),gen_random_uuid(),current_setting('test.neighbor.reverse_publication')::uuid);
 if (select count(*) from public.conversations)<>2 then raise exception 'La dirección inversa duplicó el chat';end if;
 sent:=public.send_neighbor_message(current_setting('test.neighbor.message')::uuid,current_setting('test.neighbor.message')::uuid,current_setting('test.group.neighbor')::uuid,'Respuesta unificada');
 perform public.send_neighbor_message(current_setting('test.neighbor.message')::uuid,current_setting('test.neighbor.message')::uuid,current_setting('test.group.neighbor')::uuid,'Respuesta unificada');
 if (select count(*) from public.list_neighbor_messages(current_setting('test.group.neighbor')::uuid))<>3 then raise exception 'Reintento duplicado o historial incompleto';end if;
 if not exists(select 1 from public.get_my_chat_activity(array[current_setting('test.group.publication')::uuid]) where chat_key='neighbor:'||current_setting('test.group.neighbor')) then raise exception 'Falta actividad privada';end if;
 if not exists(select 1 from public.get_my_chat_activity(array[current_setting('test.group.publication')::uuid]) where chat_key='group:'||current_setting('test.group.publication')) then raise exception 'Falta actividad grupal';end if;
end $$;
update public.publications set deleted_at=now() where id in(current_setting('test.group.publication')::uuid,current_setting('test.neighbor.publication')::uuid);
select public.send_neighbor_message(gen_random_uuid(),gen_random_uuid(),current_setting('test.group.neighbor')::uuid,'El chat continúa tras retirar los avisos');
insert into public.messages(id,client_mutation_id,conversation_id,sender_id,body)
select gen_random_uuid(),gen_random_uuid(),current_setting('test.group.private')::uuid,current_setting('test.group.author')::uuid,'Paginación '||n
from generate_series(1,205) n;
do $$ declare cursor_time timestamptz; cursor_id uuid; begin
 if (select count(*) from public.list_neighbor_messages_page(current_setting('test.group.neighbor')::uuid,null,null))<>100 then raise exception 'Primera página incompleta';end if;
 select created_at,id into cursor_time,cursor_id from public.list_neighbor_messages_page(current_setting('test.group.neighbor')::uuid,null,null) order by created_at,id limit 1;
 if (select count(*) from public.list_neighbor_messages_page(current_setting('test.group.neighbor')::uuid,cursor_time,cursor_id))<>100 then raise exception 'Segunda página incompleta';end if;
 select created_at,id into cursor_time,cursor_id from public.list_neighbor_messages_page(current_setting('test.group.neighbor')::uuid,cursor_time,cursor_id) order by created_at,id limit 1;
 if (select count(*) from public.list_neighbor_messages_page(current_setting('test.group.neighbor')::uuid,cursor_time,cursor_id))<>9 then raise exception 'Paginación perdió o duplicó mensajes';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.group.outsider'),true);
do $$ declare blocked boolean:=false; begin
 if exists(select 1 from public.list_neighbor_messages(current_setting('test.group.author')::uuid)) then raise exception 'Un tercero vio el historial privado';end if;
 if exists(select 1 from public.get_my_chat_activity(array[current_setting('test.group.publication')::uuid])) then raise exception 'Un tercero vio actividad ajena';end if;
 begin perform public.send_neighbor_message(gen_random_uuid(),gen_random_uuid(),current_setting('test.group.author')::uuid,'No autorizado');exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Un tercero envió mensajes';end if;
end $$;
reset role;
rollback;
select 'Chat único por vecino, historial, actividad, privacidad y reintentos verificados; datos de prueba revertidos' as resultado;
