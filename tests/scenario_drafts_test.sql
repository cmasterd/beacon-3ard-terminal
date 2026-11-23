\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values ('99999999-9999-4999-8999-999999999991'), ('99999999-9999-4999-8999-999999999992');
set local role anon;
do $$ begin
    begin
        perform public.game_list_my_drafts();
        raise exception 'anonymous user listed drafts';
    exception when insufficient_privilege then null; end;
    begin
        perform public.game_read_draft('11111111-1111-4111-8111-111111111111');
        raise exception 'anonymous user read draft';
    exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '99999999-9999-4999-8999-999999999991', true);
set local role authenticated;
do $$
declare
    game_id constant uuid := '11111111-1111-4111-8111-111111111111';
    first_id constant uuid := '22222222-2222-4222-8222-222222222222';
    second_id constant uuid := '33333333-3333-4333-8333-333333333333';
    package jsonb := '{"catalog":{"title":"Ghost Ship","description":"An abandoned vessel"},"definition":{"format":"vad-scenario","version":1,"initialState":{},"nodes":[{"keypadCode":"4821","logs":[{"body":"secret log"}]}]}}';
    result jsonb;
begin
    result := public.game_save_draft(game_id, first_id, 0, package);
    if result ->> 'version' <> '1' then raise exception 'first version incorrect: %', result; end if;
    perform public.game_save_draft(game_id, first_id, 0, package);
    if jsonb_array_length(public.game_list_my_drafts()) <> 1
        or public.game_list_my_drafts()::text like '%4821%'
        or public.game_list_published()::text like '%Ghost Ship%'
        or public.game_read_draft(game_id) #>> '{package,definition,nodes,0,keypadCode}' <> '4821' then
        raise exception 'draft privacy or retrieval failed';
    end if;
    begin
        perform public.game_save_draft(game_id, first_id, 0, jsonb_set(package, '{catalog,title}', '"changed"'));
        raise exception 'changed retry accepted';
    exception when invalid_parameter_value then null; end;
    package := jsonb_set(package, '{catalog,title}', '"Ghost Ship Revised"');
    perform public.game_save_draft(game_id, second_id, 1, package);
    if public.game_read_draft(game_id) ->> 'version' <> '2'
        or public.game_list_my_drafts() #>> '{0,title}' <> 'Ghost Ship Revised' then
        raise exception 'second version not saved';
    end if;
    begin
        perform public.game_save_draft(game_id, gen_random_uuid(), 1, package);
        raise exception 'stale version accepted';
    exception when serialization_failure then null; end;
    begin
        perform public.game_save_draft(gen_random_uuid(), gen_random_uuid(), 0, '{"catalog":{},"definition":{}}');
        raise exception 'invalid package accepted';
    exception when invalid_parameter_value then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '99999999-9999-4999-8999-999999999992', true);
set local role authenticated;
do $$ begin
    if jsonb_array_length(public.game_list_my_drafts()) <> 0 then raise exception 'another Warden can list drafts'; end if;
    begin
        perform public.game_read_draft('11111111-1111-4111-8111-111111111111');
        raise exception 'another Warden can read draft';
    exception when insufficient_privilege then null; end;
    begin
        perform public.game_save_draft('11111111-1111-4111-8111-111111111111', gen_random_uuid(), 2,
            '{"catalog":{"title":"Attack","description":""},"definition":{"format":"vad-scenario","version":1,"initialState":{},"nodes":[{}]}}');
        raise exception 'another Warden can modify draft';
    exception when insufficient_privilege then null; end;
end $$;
rollback;
