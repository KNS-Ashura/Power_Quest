"use strict";
//fichier directement implémenter par nakama, ne rien toucher sauf extreme urgence de fou malade
/** À chercher dans les logs Nakama (ligne « PQ module diag= ») pour confirmer que ce fichier est bien chargé. */
var MODULE_DIAG_BUILD = "power_quest-2026-04-09-op22-after-gameStart";
var MODULE_NAME = "power_quest";
var CODE_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
var CODE_LENGTH = 6;
var MAX_PLAYERS = 8;
var MIN_PLAYERS = 2;
var OP_LOBBY_STATE = 10;
var OP_PLAYER_JOINED = 11;
var OP_HOST_CHANGED = 12;
var OP_PLAYER_LEFT = 13;
var OP_GAME_START = 20;
/** Commandes client→tous (JSON validé, quota / tick). */
var OP_COMMAND = 21;
/** Snapshots ou sync volumineux : uniquement l’hôte, après game_start. */
var OP_SNAPSHOT = 22;
/** Keepalive léger (client) pendant chargement — aucun broadcast. */
var OP_RT_KEEPALIVE = 23;

var MAX_COMMAND_BYTES = 8192;
var MAX_SNAPSHOT_BYTES = 131072;
var MAX_COMMANDS_PER_SENDER_PER_TICK = 48;
var MAX_SNAPSHOTS_HOST_PER_TICK = 4;

function decodeMatchData(data) {
  if (data === null || data === undefined) {
    return "";
  }
  if (typeof data === "string") {
    return data;
  }
  try {
    return new TextDecoder().decode(data);
  } catch (e) {
    return "";
  }
}

function generateCode() {
  var code = "";
  for (var i = 0; i < CODE_LENGTH; i++) {
    code += CODE_CHARS.charAt(Math.floor(Math.random() * CODE_CHARS.length));
  }
  return code;
}

function nextAvailableSide(sideMap) {
  var used = Object.values(sideMap);
  for (var i = 0; i < MAX_PLAYERS; i++) {
    if (used.indexOf(i) === -1) return i;
  }
  return -1;
}

function broadcastJson(dispatcher, opCode, data, presences) {
  dispatcher.broadcastMessage(opCode, JSON.stringify(data), presences, null, true);
}

function matchInit(ctx, logger, nk, params) {
  var label = params["label"] !== undefined ? params["label"] : "";
  logger.info("PQ module diag=" + MODULE_DIAG_BUILD);
  logger.info("Match créé avec le code : " + label);
  return {
    state: {
      label: label,
      hostSessionId: "",
      players: {},
      playerStates: {},
      sideMap: {},
      tickCount: 0,
      emptyTicks: 0,
      gameStarted: false
    },
    tickRate: 30,
    label: label
  };
}

function matchJoinAttempt(ctx, logger, nk, dispatcher, tick, state, presence, metadata) {
  var playerCount = Object.keys(state.players).length;
  if (playerCount >= MAX_PLAYERS) {
    logger.warn("Connexion refusée : salon complet.");
    return { state: state, accept: false, rejectMessage: "Salon complet." };
  }
  return { state: state, accept: true };
}

function matchJoin(ctx, logger, nk, dispatcher, tick, state, presences) {
  for (var i = 0; i < presences.length; i++) {
    var p = presences[i];
    state.players[p.sessionId] = p;
    state.emptyTicks = 0;

    if (state.sideMap[p.sessionId] === undefined) {
      state.sideMap[p.sessionId] = nextAvailableSide(state.sideMap);
      logger.info("Side " + state.sideMap[p.sessionId] + " assigné à " + p.userId);
    }

    if (state.hostSessionId === "") {
      state.hostSessionId = p.sessionId;
      logger.info("Nouvel hôte assigné : " + p.userId);
    }
  }

  var allIds = Object.keys(state.players);
  var playersList = [];
  for (var s = 0; s < allIds.length; s++) {
    var sp = state.players[allIds[s]];
    playersList.push({
      session_id: sp.sessionId,
      user_id: sp.userId,
      username: sp.username,
      side: state.sideMap[sp.sessionId]
    });
  }

  /* Chaque joueur reçoit son lobby (side / host_user_id). L’hôte est notifié quand le 2e rejoint. */
  for (var j = 0; j < allIds.length; j++) {
    var target = state.players[allIds[j]];
    var tSide = state.sideMap[target.sessionId];
    broadcastJson(dispatcher, OP_LOBBY_STATE, {
      type: "lobby_state",
      player_count: allIds.length,
      max_players: MAX_PLAYERS,
      label: state.label,
      is_host: target.sessionId === state.hostSessionId,
      host_user_id: state.players[state.hostSessionId].userId,
      self_session_id: target.sessionId,
      side: tSide,
      players: playersList
    }, [target]);
  }

  for (var k = 0; k < presences.length; k++) {
    var pj = presences[k];
    broadcastJson(dispatcher, OP_PLAYER_JOINED, {
      type: "player_joined",
      user_id: pj.userId,
      session_id: pj.sessionId,
      player_count: allIds.length
    }, null);
  }
  return { state: state };
}

function matchLeave(ctx, logger, nk, dispatcher, tick, state, presences) {
  for (var i = 0; i < presences.length; i++) {
    var p = presences[i];
    var wasHost = (p.sessionId === state.hostSessionId);
    delete state.players[p.sessionId];

    var remaining = Object.keys(state.players);

    if (remaining.length === 0) {
      state.hostSessionId = "";
      continue;
    }

    if (wasHost) {
      state.hostSessionId = remaining[0];
      var newHost = state.players[state.hostSessionId];
      broadcastJson(dispatcher, OP_HOST_CHANGED, {
        type: "host_changed",
        new_host_user_id: newHost.userId,
        new_host_session_id: state.hostSessionId
      }, null);
    }

    delete state.playerStates[p.userId];

    broadcastJson(dispatcher, OP_PLAYER_LEFT, {
      type: "player_left",
      user_id: p.userId,
      session_id: p.sessionId,
      player_count: remaining.length
    }, null);
  }
  return { state: state };
}

function matchLoop(ctx, logger, nk, dispatcher, tick, state, messages) {
  state.tickCount = tick;
  var cmdCounts = {};
  var snapHostCount = 0;

  for (var i = 0; i < messages.length; i++) {
    var msg = messages[i];
    var sender = state.players[msg.sender.sessionId];
    if (!sender) {
      continue;
    }

    if (msg.opCode === OP_RT_KEEPALIVE) {
      continue;
    }

    if (msg.opCode === OP_GAME_START && msg.sender.sessionId === state.hostSessionId && !state.gameStarted && Object.keys(state.players).length >= MIN_PLAYERS) {
      state.gameStarted = true;
      var hostUserId = state.players[state.hostSessionId].userId;
      broadcastJson(dispatcher, OP_GAME_START, {
        type: "game_start",
        started_at_tick: tick,
        host_user_id: hostUserId
      }, null);
      continue;
    }

    if (msg.opCode === OP_COMMAND) {
      var sid = msg.sender.sessionId;
      var c = cmdCounts[sid] || 0;
      if (c >= MAX_COMMANDS_PER_SENDER_PER_TICK) {
        logger.warn("Command quota dépassée: " + sid);
        continue;
      }
      var rawCmd = decodeMatchData(msg.data);
      if (rawCmd.length === 0 || rawCmd.length > MAX_COMMAND_BYTES) {
        continue;
      }
      var obj;
      try {
        obj = JSON.parse(rawCmd);
      } catch (e) {
        continue;
      }
      if (!obj || typeof obj !== "object") {
        continue;
      }
      obj._net = {
        from_user_id: sender.userId,
        from_session_id: sid,
        /** 0 = hôte du salon, 1 = invité (aligné sur lobby_state.side Nakama). */
        server_side: sender.sessionId === state.hostSessionId ? 0 : 1,
        server_tick: tick
      };
      cmdCounts[sid] = c + 1;
      broadcastJson(dispatcher, OP_COMMAND, obj, null);
      continue;
    }

    if (msg.opCode === OP_SNAPSHOT) {
      if (msg.sender.sessionId !== state.hostSessionId || !state.gameStarted) {
        continue;
      }
      if (snapHostCount >= MAX_SNAPSHOTS_HOST_PER_TICK) {
        continue;
      }
      var rawSnap = decodeMatchData(msg.data);
      if (rawSnap.length === 0 || rawSnap.length > MAX_SNAPSHOT_BYTES) {
        continue;
      }
      var snapObj;
      try {
        snapObj = JSON.parse(rawSnap);
      } catch (e) {
        continue;
      }
      if (!snapObj || typeof snapObj !== "object") {
        continue;
      }
      snapObj._net = {
        from_user_id: sender.userId,
        from_session_id: msg.sender.sessionId,
        server_tick: tick,
        frame: "snapshot"
      };
      snapHostCount += 1;
      broadcastJson(dispatcher, OP_SNAPSHOT, snapObj, null);
    }
  }

  if (Object.keys(state.players).length === 0) {
    state.emptyTicks++;
    if (state.emptyTicks > 300) {
      logger.info("Match inactif terminé.");
      return null;
    }
  } else {
    state.emptyTicks = 0;
  }
  return { state: state };
}

function matchSignal(ctx, logger, nk, dispatcher, tick, state, data) {
  return { state: state };
}

function matchTerminate(ctx, logger, nk, dispatcher, tick, state, graceSeconds) {
  broadcastJson(dispatcher, 99, { type: "match_terminated" }, null);
  return { state: state };
}

function rpcCreatePrivateMatch(ctx, logger, nk, payload) {
  var code = generateCode();
  var matchId;
  try {
    matchId = nk.matchCreate(MODULE_NAME, { label: code });
  } catch (e) {
    logger.error("Erreur de création: " + e.message);
    throw new Error("Impossible de créer le match.");
  }
  logger.info("Salon créé - Code: " + code + " ID: " + matchId);
  return JSON.stringify({ code: code, match_id: matchId });
}

function rpcJoinMatchByLabel(ctx, logger, nk, payload) {
  if (!payload) throw new Error("Payload requis.");

  var data;
  try {
    data = JSON.parse(payload);
  } catch (e) {
    throw new Error("JSON invalide.");
  }

  if (!data.code || data.code.length !== CODE_LENGTH) {
    throw new Error("Code invalide.");
  }

  var code = data.code.toUpperCase().trim();
  var matches = nk.matchList(5, true, code, 0, MAX_PLAYERS - 1, "");

  if (!matches || matches.length === 0) {
    throw new Error("Salon introuvable ou complet.");
  }

  var match = matches[0];
  logger.info("Salon rejoint - Code: " + code);
  return JSON.stringify({ match_id: match.matchId });
}

function rpcFindPublicMatch(ctx, logger, nk, payload) {
  var matches = nk.matchList(20, true, "PUBLIC", 0, MAX_PLAYERS - 1, "");
  if (matches && matches.length > 0) {
    logger.info("Salon public trouvé: " + matches[0].matchId);
    return JSON.stringify({ match_id: matches[0].matchId, created: false });
  }

  var matchId;
  try {
    matchId = nk.matchCreate(MODULE_NAME, { label: "PUBLIC" });
  } catch (e) {
    logger.error("Erreur création public: " + e.message);
    throw new Error("Impossible de créer un salon public.");
  }

  logger.info("Salon public créé: " + matchId);
  return JSON.stringify({ match_id: matchId, created: true });
}

function InitModule(ctx, logger, nk, initializer) {
  initializer.registerMatch(MODULE_NAME, {
    matchInit: matchInit,
    matchJoinAttempt: matchJoinAttempt,
    matchJoin: matchJoin,
    matchLeave: matchLeave,
    matchLoop: matchLoop,
    matchSignal: matchSignal,
    matchTerminate: matchTerminate
  });

  initializer.registerRpc("create_private_match", rpcCreatePrivateMatch);
  initializer.registerRpc("join_match_by_label", rpcJoinMatchByLabel);
  initializer.registerRpc("find_public_match", rpcFindPublicMatch);

  logger.info("Module Power Quest prêt et chargé avec succès !");
}