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
local FAST_START_COUNTDOWN_SEC = 5
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


local function countdown_duration_for_players(count)
	if count >= MAX_PLAYERS then
		return FAST_START_COUNTDOWN_SEC
	end
	if count >= MIN_PLAYERS then
		return MATCH_COUNTDOWN_SEC
	end
	return 0
end


-- Dès 2 joueurs : 10 s (reset à chaque join). À 8 joueurs : 5 s.
local function evaluate_queue_after_change(queue)
	local count = #queue
	if count < MIN_PLAYERS then
		write_queue(queue, now_ts(), 0)
		return encode_waiting(count, 0)
	end

	local duration = countdown_duration_for_players(count)
	local match_starts_at = now_ts() + duration
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
		local duration = countdown_duration_for_players(count)
		match_starts_at = now_ts() + duration
		write_queue(queue, now_ts(), match_starts_at)
		seconds_left = duration
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


local function decode_json_payload(payload)
	if payload == nil or payload == "" then
		return {}
	end
	local ok, parsed = pcall(nk.json_decode, payload)
	if not ok or parsed == nil then
		return {}
	end
	if type(parsed) == "string" and parsed ~= "" then
		local ok2, parsed2 = pcall(nk.json_decode, parsed)
		if ok2 and parsed2 ~= nil then
			return parsed2
		end
		return {}
	end
	return parsed
end


local function rpc_set_username(context, payload)
	local data = decode_json_payload(payload)
	local username = tostring(data.username or "")
	username = username:match("^%s*(.-)%s*$") or ""
	if #username < 3 or #username > 20 then
		return nk.json_encode({ status = "error", message = "invalid_username" })
	end
	if not username:match("^[a-zA-Z0-9_]+$") then
		return nk.json_encode({ status = "error", message = "invalid_username" })
	end

	local user_id = context.user_id
	local ok, err = pcall(nk.account_update_id, user_id, {}, username, username, nil, nil, nil, nil)
	if not ok then
		nk.logger_warn("set_username failed: " .. tostring(err))
		return nk.json_encode({ status = "error", message = tostring(err) })
	end
	return nk.json_encode({ status = "ok", username = username })
end

local function read_recent_results(user_id)
	local objects = nk.storage_read({
		{ collection = STATS_COLLECTION, key = STATS_KEY, user_id = user_id },
	})
	if objects == nil or #objects == 0 then
		return {}
	end
	local value = objects[1].value or {}
	if type(value.recent) == "table" then
		return value.recent
	end
	return {}
end


local function write_recent_results(user_id, recent)
	nk.storage_write({
		{
			collection = STATS_COLLECTION,
			key = STATS_KEY,
			user_id = user_id,
			value = { recent = recent, updated_at = now_ts() },
			permission_read = 2,
			permission_write = 0,
		},
	})
end


local function read_legacy_stats(user_id)
	local objects = nk.storage_read({
		{ collection = STATS_COLLECTION, key = STATS_KEY, user_id = user_id },
	})
	if objects == nil or #objects == 0 then
		return nil
	end
	local value = objects[1].value or {}
	if value.games == nil then
		return nil
	end
	return value
end


local function read_profile_from_leaderboard(user_id, username)
	local games = 0
	local wins = 0
	local losses = 0
	local total_seconds = 0
	local winrate = 0.0
	local level = 0

	local ok, result = pcall(nk.leaderboard_records_list, LEADERBOARD_ID, { user_id }, 1, user_id, 0)
	if ok and result ~= nil and result.records ~= nil and #result.records > 0 then
		local rec = result.records[1]
		local score = tonumber(rec.score or 0) or 0
		winrate = score / 1000.0
		wins = tonumber(rec.subscore or 0) or 0
		if rec.metadata ~= nil then
			games = tonumber(rec.metadata.games or 0) or 0
			total_seconds = tonumber(rec.metadata.total_seconds or 0) or 0
		end
		losses = games - wins
		if losses < 0 then
			losses = 0
		end
	else
		local legacy = read_legacy_stats(user_id)
		if legacy ~= nil then
			games = tonumber(legacy.games or 0) or 0
			wins = tonumber(legacy.wins or 0) or 0
			losses = tonumber(legacy.losses or 0) or 0
			total_seconds = tonumber(legacy.total_seconds or 0) or 0
			level = tonumber(legacy.level or 0) or 0
			winrate = tonumber(legacy.winrate or 0) or 0
		end
	end

	if level <= 0 and games > 0 then
		level = math.floor(games / 3)
	end

	local recent = read_recent_results(user_id)
	return {
		user_id = user_id,
		username = username,
		level = level,
		games = games,
		wins = wins,
		losses = losses,
		winrate = winrate,
		total_seconds = total_seconds,
		recent = recent,
	}
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

	local profile = read_profile_from_leaderboard(user_id, username)
	profile.games = profile.games + 1
	if win then
		profile.wins = profile.wins + 1
	else
		profile.losses = profile.losses + 1
	end
	profile.total_seconds = profile.total_seconds + duration_seconds
	if profile.games > 0 then
		profile.winrate = (profile.wins / profile.games) * 100.0
	end
	profile.level = math.floor(profile.games / 3)

	table.insert(profile.recent, 1, win and "W" or "L")
	while #profile.recent > 10 do
		table.remove(profile.recent)
	end
	write_recent_results(user_id, profile.recent)

	local score = math.floor(profile.winrate * 1000.0)
	local subscore = profile.wins
	pcall(nk.leaderboard_record_write, LEADERBOARD_ID, user_id, username, score, subscore, {
		games = profile.games,
		winrate = profile.winrate,
		total_seconds = profile.total_seconds,
	})

	return nk.json_encode({
		status = "ok",
		games = profile.games,
		wins = profile.wins,
		losses = profile.losses,
		winrate = profile.winrate,
		total_seconds = profile.total_seconds,
		recent = profile.recent,
	})
end

local function rpc_get_player_profile(context, payload)
	local username = context.username or ""
	if username == context.user_id then
		username = ""
	end
	local profile = read_profile_from_leaderboard(context.user_id, username)
	return nk.json_encode(profile)
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

nk.register_rpc(rpc_set_username, "set_username")
nk.register_rpc(rpc_join_queue, "join_queue")
nk.register_rpc(rpc_leave_queue, "leave_queue")
nk.register_rpc(rpc_queue_status, "queue_status")
nk.register_rpc(rpc_ping, "ping")
nk.register_rpc(rpc_submit_match_result, "submit_match_result")
nk.register_rpc(rpc_get_player_profile, "get_player_profile")
nk.register_rpc(rpc_get_leaderboard, "get_leaderboard")
ensure_leaderboard()

nk.logger_info(string.format(
	"Power Quest lobby loaded (countdown %ds, fast start %ds at %d players)",
	MATCH_COUNTDOWN_SEC,
	FAST_START_COUNTDOWN_SEC,
	MAX_PLAYERS
))
