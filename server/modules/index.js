"use strict";
//fichier directement implémenter par nakama, ne rien toucher sauf extreme urgence de fou malade
var MODULE_NAME = "power_quest";
var CODE_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
var CODE_LENGTH = 6;
var MAX_PLAYERS = 2;

function generateCode() {
  var code = "";
  for (var i = 0; i < CODE_LENGTH; i++) {
    code += CODE_CHARS.charAt(Math.floor(Math.random() * CODE_CHARS.length));
  }
  return code;
}

function broadcastJson(dispatcher, opCode, data, presences) {
  dispatcher.broadcastMessage(opCode, JSON.stringify(data), presences, null, true);
}

function matchInit(ctx, logger, nk, params) {
  var label = params["label"] !== undefined ? params["label"] : "";
  logger.info("Match créé avec le code : " + label);
  return {
    state: {
      label: label,
      hostSessionId: "",
      players: {},
      tickCount: 0,
      emptyTicks: 0
    },
    tickRate: 5,
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

    if (state.hostSessionId === "") {
      state.hostSessionId = p.sessionId;
      logger.info("Nouvel hôte assigné : " + p.userId);
    }

    broadcastJson(dispatcher, 10, {
      type: "lobby_state",
      player_count: Object.keys(state.players).length,
      max_players: MAX_PLAYERS,
      label: state.label,
      is_host: (p.sessionId === state.hostSessionId)
    }, [p]);

    broadcastJson(dispatcher, 11, {
      type: "player_joined",
      user_id: p.userId,
      player_count: Object.keys(state.players).length
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
      broadcastJson(dispatcher, 12, {
        type: "host_changed",
        new_host_user_id: newHost.userId,
        new_host_session_id: state.hostSessionId
      }, null);
    }

    broadcastJson(dispatcher, 13, {
      type: "player_left",
      user_id: p.userId,
      player_count: remaining.length
    }, null);
  }
  return { state: state };
}

function matchLoop(ctx, logger, nk, dispatcher, tick, state, messages) {
  state.tickCount = tick;

  if (Object.keys(state.players).length === 0) {
    state.emptyTicks++;
    if (state.emptyTicks > 25) {
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

  logger.info("Module Power Quest prêt et chargé avec succès !");
}