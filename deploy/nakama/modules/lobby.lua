-- Power Quest — lobby Nakama (Lua, fiable sur Nakama 3.x)
-- File à 2 joueurs min. Compte à rebours 10 s dès 2 joueurs (reset à chaque arrivée).

local nk = require("nakama")

local QUEUE_COLLECTION = "pq_lobby"
local QUEUE_KEY = "global_queue"
local PENDING_KEY_PREFIX = "pending_match:"
local SYSTEM_USER = "00000000-0000-0000-0000-000000000000"
local GAME_WS_URL = "wss://powerquest.robinmatelot.codes/game/"
local STATS_COLLECTION = "pq_stats"
local STATS_KEY = "profile"
local LEADERBOARD_ID = "pq_winrate"
local MIN_PLAYERS = 2
local MAX_PLAYERS = 8
local MATCH_COUNTDOWN_SEC = 10
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
		return {}, 0, 0
	end
	local value = objects[1].value
	if value == nil or value.user_ids == nil then
		return {}, 0, 0
	end
	return value.user_ids, value.updated_at or 0, value.match_starts_at or 0
end

local function write_queue(queue, updated_at, match_starts_at)
	nk.storage_write({
		{
			collection = QUEUE_COLLECTION,
			key = QUEUE_KEY,
			user_id = SYSTEM_USER,
			value = {
				user_ids = queue,
				updated_at = updated_at or now_ts(),
				match_starts_at = match_starts_at or 0,
			},
			permission_read = 0,
			permission_write = 0,
		},
	})
end

local function read_queue_state()
	local queue, updated_at, match_starts_at = read_queue_raw()
	if updated_at > 0 and (now_ts() - updated_at) > QUEUE_TTL_SEC then
		nk.logger_info("Power Quest lobby: file expirée, reset")
		write_queue({}, now_ts(), 0)
		return {}, 0
	end
	if #queue < MIN_PLAYERS then
		match_starts_at = 0
	end
	return queue, match_starts_at
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

local function encode_waiting(count, seconds_left)
	return nk.json_encode({
		status = "waiting",
		players = count,
		max_players = MAX_PLAYERS,
		seconds_left = seconds_left,
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
		return encode_waiting(#queue, 0)
	end
	local match_id = nk.uuid_v4()
	local count = #queue
	for _, uid in ipairs(queue) do
		write_pending_match(uid, match_id, count)
	end
	write_queue({}, now_ts(), 0)
	nk.logger_info(string.format("Power Quest lobby: match %s — %d joueurs.", match_id, count))
	return encode_matched(match_id, count)
end

local function queue_countdown_seconds(match_starts_at)
	if match_starts_at <= 0 then
		return 0
	end
	local left = match_starts_at - now_ts()
	if left < 0 then
		return 0
	end
	return left
end

-- Dès 2 joueurs : compte à rebours 10 s (réinitialisé à chaque nouveau joueur).
local function evaluate_queue_after_change(queue)
	local count = #queue
	if count < MIN_PLAYERS then
		write_queue(queue, now_ts(), 0)
		return encode_waiting(count, 0)
	end

	local match_starts_at = now_ts() + MATCH_COUNTDOWN_SEC
	write_queue(queue, now_ts(), match_starts_at)
	local seconds_left = queue_countdown_seconds(match_starts_at)
	if seconds_left <= 0 then
		return create_match_for_queue(queue)
	end
	return encode_waiting(count, seconds_left)
end

local function evaluate_queue_status(queue, match_starts_at)
	local count = #queue
	if count < MIN_PLAYERS then
		return encode_waiting(count, 0)
	end

	local seconds_left = queue_countdown_seconds(match_starts_at)
	if match_starts_at <= 0 then
		match_starts_at = now_ts() + MATCH_COUNTDOWN_SEC
		write_queue(queue, now_ts(), match_starts_at)
		seconds_left = MATCH_COUNTDOWN_SEC
	end

	if seconds_left <= 0 then
		return create_match_for_queue(queue)
	end
	return encode_waiting(count, seconds_left)
end

local function rpc_join_queue(context, payload)
	local user_id = context.user_id

	local pending_response = try_consume_pending(user_id)
	if pending_response ~= nil then
		return pending_response
	end

	local queue, match_starts_at = read_queue_state()

	if not user_in_queue(queue, user_id) then
		table.insert(queue, user_id)
	end

	return evaluate_queue_after_change(queue)
end

local function rpc_leave_queue(context, payload)
	local user_id = context.user_id
	clear_pending_match(user_id)
	local queue, match_starts_at = read_queue_state()
	local new_queue = {}
	for _, uid in ipairs(queue) do
		if uid ~= user_id then
			table.insert(new_queue, uid)
		end
	end
	if #new_queue < MIN_PLAYERS then
		write_queue(new_queue, now_ts(), 0)
	else
		write_queue(new_queue, now_ts(), match_starts_at)
	end
	return nk.json_encode({ status = "left", players = #new_queue })
end

local function rpc_queue_status(context, payload)
	local user_id = context.user_id

	local pending_response = try_consume_pending(user_id)
	if pending_response ~= nil then
		return pending_response
	end

	local queue, match_starts_at = read_queue_state()
	if user_in_queue(queue, user_id) then
		return evaluate_queue_status(queue, match_starts_at)
	end
	return encode_waiting(#queue, queue_countdown_seconds(match_starts_at))
end

local function rpc_ping(context, payload)
	return nk.json_encode({ status = "ok", module = "lobby.lua" })
end

local function default_stats(user_id)
	return {
		user_id = user_id,
		username = "",
		level = 0,
		games = 0,
		wins = 0,
		losses = 0,
		winrate = 0.0,
		total_seconds = 0,
		recent = {},
		updated_at = now_ts(),
	}
end

local function read_stats(user_id)
	local objects = nk.storage_read({
		{ collection = STATS_COLLECTION, key = STATS_KEY, user_id = user_id },
	})
	if objects == nil or #objects == 0 then
		return default_stats(user_id)
	end
	local value = objects[1].value or {}
	value.user_id = user_id
	value.games = tonumber(value.games or 0) or 0
	value.wins = tonumber(value.wins or 0) or 0
	value.losses = tonumber(value.losses or 0) or 0
	value.total_seconds = tonumber(value.total_seconds or 0) or 0
	value.level = tonumber(value.level or 0) or 0
	value.recent = value.recent or {}
	value.winrate = 0.0
	if value.games > 0 then
		value.winrate = (value.wins / value.games) * 100.0
	end
	return value
end

local function write_stats(user_id, stats)
	stats.updated_at = now_ts()
	nk.storage_write({
		{
			collection = STATS_COLLECTION,
			key = STATS_KEY,
			user_id = user_id,
			value = stats,
			permission_read = 2,
			permission_write = 0,
		},
	})
end

local function ensure_leaderboard()
	local ok, err = pcall(nk.leaderboard_create, LEADERBOARD_ID, false, "desc", "best", "", {}, true)
	if not ok then
		nk.logger_warn("leaderboard_create failed (ignored): " .. tostring(err))
	end
end

local function rpc_submit_match_result(context, payload)
	local user_id = context.user_id
	local username = context.username or ""
	local data = {}
	if payload ~= nil and payload ~= "" then
		local ok, parsed = pcall(nk.json_decode, payload)
		if ok and parsed ~= nil then
			data = parsed
			if type(data) == "string" and data ~= "" then
				local ok2, parsed2 = pcall(nk.json_decode, data)
				if ok2 and parsed2 ~= nil then
					data = parsed2
				end
			end
		end
	end

	local win = data.win == true
	local duration_seconds = tonumber(data.duration_seconds or 0) or 0
	if duration_seconds < 0 then duration_seconds = 0 end

	local stats = read_stats(user_id)
	stats.username = username
	stats.games = stats.games + 1
	if win then
		stats.wins = stats.wins + 1
	else
		stats.losses = stats.losses + 1
	end
	stats.total_seconds = stats.total_seconds + duration_seconds
	stats.winrate = (stats.wins / stats.games) * 100.0

	table.insert(stats.recent, 1, win and "W" or "L")
	while #stats.recent > 10 do
		table.remove(stats.recent)
	end
	write_stats(user_id, stats)

	local score = math.floor(stats.winrate * 1000.0)
	local subscore = stats.wins
	pcall(nk.leaderboard_record_write, LEADERBOARD_ID, user_id, username, score, subscore, {
		games = stats.games,
		winrate = stats.winrate,
		total_seconds = stats.total_seconds,
	})

	return nk.json_encode({
		status = "ok",
		games = stats.games,
		wins = stats.wins,
		losses = stats.losses,
		winrate = stats.winrate,
		total_seconds = stats.total_seconds,
		recent = stats.recent,
	})
end

local function rpc_get_player_profile(context, payload)
	local stats = read_stats(context.user_id)
	local username = context.username or ""
	if username == "" then
		username = stats.username or ""
	end
	if username == context.user_id then
		username = ""
	end
	stats.username = username
	write_stats(context.user_id, stats)
	return nk.json_encode(stats)
end

local function rpc_get_leaderboard(context, payload)
	local req = {}
	if payload ~= nil and payload ~= "" then
		local ok, parsed = pcall(nk.json_decode, payload)
		if ok and parsed ~= nil then
			req = parsed
			if type(req) == "string" and req ~= "" then
				local ok2, parsed2 = pcall(nk.json_decode, req)
				if ok2 and parsed2 ~= nil then
					req = parsed2
				end
			end
		end
	end
	local limit = tonumber(req.limit or 20) or 20
	if limit < 1 then limit = 1 end
	if limit > 100 then limit = 100 end

	local ok, records = pcall(nk.leaderboard_records_list, LEADERBOARD_ID, {}, limit, "")
	if not ok or records == nil then
		return nk.json_encode({ entries = {} })
	end

	local entries = {}
	for _, rec in ipairs(records) do
		local score = tonumber(rec.score or 0) or 0
		local winrate = score / 1000.0
		table.insert(entries, {
			user_id = rec.owner_id,
			username = rec.username or "",
			winrate = winrate,
			games = rec.metadata and rec.metadata.games or 0,
			total_seconds = rec.metadata and rec.metadata.total_seconds or 0,
		})
	end
	return nk.json_encode({ entries = entries })
end

nk.register_rpc(rpc_join_queue, "join_queue")
nk.register_rpc(rpc_leave_queue, "leave_queue")
nk.register_rpc(rpc_queue_status, "queue_status")
nk.register_rpc(rpc_ping, "ping")
nk.register_rpc(rpc_submit_match_result, "submit_match_result")
nk.register_rpc(rpc_get_player_profile, "get_player_profile")
nk.register_rpc(rpc_get_leaderboard, "get_leaderboard")
ensure_leaderboard()

nk.logger_info(string.format("Power Quest lobby module loaded (countdown %ds)", MATCH_COUNTDOWN_SEC))
