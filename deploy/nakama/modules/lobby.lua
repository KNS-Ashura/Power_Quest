-- Power Quest — lobby Nakama (Lua, fiable sur Nakama 3.x)
-- File à 2 joueurs min. Pending + queue expirent pour éviter un faux "matched" solo.

local nk = require("nakama")

local QUEUE_COLLECTION = "pq_lobby"
local QUEUE_KEY = "global_queue"
local PENDING_KEY_PREFIX = "pending_match:"
local SYSTEM_USER = "00000000-0000-0000-0000-000000000000"
local GAME_WS_URL = "wss://powerquest.robinmatelot.codes/game/"
local MIN_PLAYERS = 2
local MAX_PLAYERS = 8
local QUEUE_TTL_SEC = 90
local PENDING_TTL_SEC = 120

local function now_ts()
	return os.time()
end

local function read_queue_raw()
	local objects = nk.storage_read({
		{ collection = QUEUE_COLLECTION, key = QUEUE_KEY, user_id = SYSTEM_USER },
	})
	if objects == nil or #objects == 0 then
		return {}, 0
	end
	local value = objects[1].value
	if value == nil or value.user_ids == nil then
		return {}, 0
	end
	return value.user_ids, value.updated_at or 0
end

local function write_queue(queue, updated_at)
	nk.storage_write({
		{
			collection = QUEUE_COLLECTION,
			key = QUEUE_KEY,
			user_id = SYSTEM_USER,
			value = {
				user_ids = queue,
				updated_at = updated_at or now_ts(),
			},
			permission_read = 0,
			permission_write = 0,
		},
	})
end

local function read_queue()
	local queue, updated_at = read_queue_raw()
	if updated_at > 0 and (now_ts() - updated_at) > QUEUE_TTL_SEC then
		nk.logger_info("Power Quest lobby: file expirée, reset")
		write_queue({})
		return {}
	end
	return queue
end

local function user_in_queue(queue, user_id)
	for _, uid in ipairs(queue) do
		if uid == user_id then
			return true
		end
	end
	return false
end

local function read_pending_match(user_id)
	local objects = nk.storage_read({
		{
			collection = QUEUE_COLLECTION,
			key = PENDING_KEY_PREFIX .. user_id,
			user_id = SYSTEM_USER,
		},
	})
	if objects == nil or #objects == 0 then
		return nil
	end
	return objects[1].value
end

local function write_pending_match(user_id, match_id, players)
	nk.storage_write({
		{
			collection = QUEUE_COLLECTION,
			key = PENDING_KEY_PREFIX .. user_id,
			user_id = SYSTEM_USER,
			value = {
				match_id = match_id,
				game_ws_url = GAME_WS_URL,
				players = players,
				created_at = now_ts(),
			},
			permission_read = 0,
			permission_write = 0,
		},
	})
end

local function clear_pending_match(user_id)
	nk.storage_delete({
		{
			collection = QUEUE_COLLECTION,
			key = PENDING_KEY_PREFIX .. user_id,
			user_id = SYSTEM_USER,
		},
	})
end

local function encode_matched(match_id, players)
	return nk.json_encode({
		status = "matched",
		players = players,
		max_players = MAX_PLAYERS,
		match_id = match_id,
		game_ws_url = GAME_WS_URL,
		seconds_left = 0,
	})
end

local function encode_waiting(count)
	return nk.json_encode({
		status = "waiting",
		players = count,
		max_players = MAX_PLAYERS,
		seconds_left = 60,
		match_id = "",
		game_ws_url = "",
	})
end

local function try_consume_pending(user_id)
	local pending = read_pending_match(user_id)
	if pending == nil then
		return nil
	end
	local created = pending.created_at or 0
	if created > 0 and (now_ts() - created) > PENDING_TTL_SEC then
		clear_pending_match(user_id)
		nk.logger_info("Power Quest lobby: pending expiré pour " .. user_id)
		return nil
	end
	local players = pending.players or 0
	if players < MIN_PLAYERS then
		clear_pending_match(user_id)
		return nil
	end
	clear_pending_match(user_id)
	return encode_matched(pending.match_id or nk.uuid_v4(), players)
end

local function create_match_for_queue(queue)
	if #queue < MIN_PLAYERS then
		return encode_waiting(#queue)
	end
	local match_id = nk.uuid_v4()
	local count = #queue
	for _, uid in ipairs(queue) do
		write_pending_match(uid, match_id, count)
	end
	write_queue({})
	return encode_matched(match_id, count)
end

local function rpc_join_queue(context, payload)
	local user_id = context.user_id

	local pending_response = try_consume_pending(user_id)
	if pending_response ~= nil then
		return pending_response
	end

	local queue = read_queue()

	if not user_in_queue(queue, user_id) then
		table.insert(queue, user_id)
		write_queue(queue)
	end

	local count = #queue
	if count >= MIN_PLAYERS then
		return create_match_for_queue(queue)
	end

	return encode_waiting(count)
end

local function rpc_leave_queue(context, payload)
	local user_id = context.user_id
	clear_pending_match(user_id)
	local queue = read_queue()
	local new_queue = {}
	for _, uid in ipairs(queue) do
		if uid ~= user_id then
			table.insert(new_queue, uid)
		end
	end
	write_queue(new_queue)
	return nk.json_encode({ status = "left", players = #new_queue })
end

local function rpc_queue_status(context, payload)
	local user_id = context.user_id

	local pending_response = try_consume_pending(user_id)
	if pending_response ~= nil then
		return pending_response
	end

	local queue = read_queue()
	local count = #queue
	if user_in_queue(queue, user_id) then
		return encode_waiting(count)
	end
	return encode_waiting(count)
end

local function rpc_ping(context, payload)
	return nk.json_encode({ status = "ok", module = "lobby.lua" })
end

nk.register_rpc(rpc_join_queue, "join_queue")
nk.register_rpc(rpc_leave_queue, "leave_queue")
nk.register_rpc(rpc_queue_status, "queue_status")
nk.register_rpc(rpc_ping, "ping")

nk.logger_info("Power Quest lobby module loaded (Lua, TTL queue/pending)")
