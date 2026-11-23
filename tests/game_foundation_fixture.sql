-- Insert a legacy session before applying game_foundation.sql.
\set ON_ERROR_STOP on
insert into auth.users(id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
insert into beacon_private.sessions
    (owner_id, join_code, player_code, shared, private_data, groups, presence, ship_data, reset_epoch)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', repeat('a', 64), 'ABCDE',
    '{"vad_shared_station_state_v14":{"2":{"explored":true}}}',
    '{"vad_warden_notes_v1":"Private notes"}',
    '{"1":true,"2":true,"3":false,"4":false}',
    '{"1":{"room":"4","time":10},"2":{"room":"3","time":10}}',
    '{"name":"Existing ship","rooms":[]}', 7);
insert into beacon_private.ship_requests (owner_id, request_id, group_number, item_id, quantity)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 2, 'up_armor', 1);
