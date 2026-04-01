// Power Quest - Nakama Authoritative Match Module
// Compile: npx esbuild index.ts --bundle --outfile=build/index.js --platform=node --target=es5

const MODULE_NAME = "power_quest";
const CODE_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const CODE_LENGTH = 6;
const MAX_PLAYERS = 2;

// ─── Types ────────────────────────────────────────────────────────────────────

interface MatchState {
  label: string;
  hostSessionId: string;
  players: { [sessionId: string]: nkruntime.Presence };
  tickCount: number;
  emptyTicks: number;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function generateCode(): string {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_CHARS.charAt(Math.floor(Math.random() * CODE_CHARS.length));
  }
  return code;
}

function broadcastJson(dispatcher: nkruntime.MatchDispatcher, opCode: number, data: object, presences: nkruntime.Presence[] | null = null): void {
  dispatcher.broadcastMessage(opCode, JSON.stringify(data), presences, null, true);
}

// ─── Match Lifecycle ──────────────────────────────────────────────────────────

const matchInit: nkruntime.MatchInitFunction<MatchState> = (
  _ctx, logger, _nk, params
) => {
  const label = params["label"] ?? "";
  logger.info(`[${MODULE_NAME}] matchInit - label: ${label}`);

  return {
    state: {
      label,
      hostSessionId: "",
      players: {},
      tickCount: 0,
      emptyTicks: 0,
    },
    tickRate: 5,
    label,
  };
};

const matchJoinAttempt: nkruntime.MatchJoinAttemptFunction<MatchState> = (
  _ctx, logger, _nk, _dispatcher, _tick, state, presence, _metadata
) => {
  const playerCount = Object.keys(state.players).length;

  if (playerCount >= MAX_PLAYERS) {
    logger.warn(`[${MODULE_NAME}] Join refused for ${presence.userId} - match full (${playerCount}/${MAX_PLAYERS})`);
    return { state, accept: false, rejectMessage: "Salon complet." };
  }

  logger.info(`[${MODULE_NAME}] Join accepted for ${presence.userId}`);
  return { state, accept: true };
};

const matchJoin: nkruntime.MatchJoinFunction<MatchState> = (
  _ctx, logger, _nk, dispatcher, _tick, state, presences
) => {
  for (const p of presences) {
    state.players[p.sessionId] = p;
    state.emptyTicks = 0;

    // Premier joueur = hôte
    if (state.hostSessionId === "") {
      state.hostSessionId = p.sessionId;
      logger.info(`[${MODULE_NAME}] Host assigned: ${p.userId}`);
    }

    // Notifier le rejoignant de l'état actuel
    broadcastJson(dispatcher, 10, {
      type: "lobby_state",
      player_count: Object.keys(state.players).length,
      max_players: MAX_PLAYERS,
      label: state.label,
      is_host: p.sessionId === state.hostSessionId,
    }, [p]);

    // Notifier les autres de l'arrivée
    broadcastJson(dispatcher, 11, {
      type: "player_joined",
      user_id: p.userId,
      player_count: Object.keys(state.players).length,
    });

    logger.info(`[${MODULE_NAME}] Player joined: ${p.userId} (${Object.keys(state.players).length}/${MAX_PLAYERS})`);
  }

  return { state };
};

const matchLeave: nkruntime.MatchLeaveFunction<MatchState> = (
  _ctx, logger, _nk, dispatcher, _tick, state, presences
) => {
  for (const p of presences) {
    const wasHost = p.sessionId === state.hostSessionId;
    delete state.players[p.sessionId];

    logger.info(`[${MODULE_NAME}] Player left: ${p.userId} (was_host: ${wasHost})`);

    const remaining = Object.keys(state.players);

    if (remaining.length === 0) {
      state.hostSessionId = "";
      logger.info(`[${MODULE_NAME}] Match empty after leave`);
      continue;
    }

    // Transfert de l'hôte si l'hôte est parti
    if (wasHost) {
      state.hostSessionId = remaining[0];
      const newHost = state.players[state.hostSessionId];

      broadcastJson(dispatcher, 12, {
        type: "host_changed",
        new_host_user_id: newHost.userId,
        new_host_session_id: state.hostSessionId,
      });

      logger.info(`[${MODULE_NAME}] Host transferred to: ${newHost.userId}`);
    }

    broadcastJson(dispatcher, 13, {
      type: "player_left",
      user_id: p.userId,
      player_count: remaining.length,
    });
  }

  return { state };
};

const matchLoop: nkruntime.MatchLoopFunction<MatchState> = (
  _ctx, logger, _nk, _dispatcher, tick, state, _messages
) => {
  state.tickCount = tick;

  if (Object.keys(state.players).length === 0) {
    state.emptyTicks++;
    // Fermer le match après 5 secondes vide (tickRate=5 → 25 ticks)
    if (state.emptyTicks > 25) {
      logger.info(`[${MODULE_NAME}] Match ${state.label} terminé (inactif)`);
      return null; // Termine le match
    }
  } else {
    state.emptyTicks = 0;
  }

  return { state };
};

const matchTerminate: nkruntime.MatchTerminateFunction<MatchState> = (
  _ctx, logger, _nk, dispatcher, _tick, state, _graceSeconds
) => {
  logger.info(`[${MODULE_NAME}] Match terminé: ${state.label}`);
  broadcastJson(dispatcher, 99, { type: "match_terminated" });
  return { state };
};

const matchSignal: nkruntime.MatchSignalFunction<MatchState> = (
  _ctx, _logger, _nk, _dispatcher, _tick, state, data
) => {
  return { state, data };
};

// ─── RPC: create_private_match ────────────────────────────────────────────────

const rpcCreatePrivateMatch: nkruntime.RpcFunction = (_ctx, logger, nk, _payload): string => {
  const code = generateCode();

  let matchId: string;
  try {
    matchId = nk.matchCreate(MODULE_NAME, { label: code });
  } catch (e) {
    logger.error(`[${MODULE_NAME}] matchCreate failed: ${e}`);
    throw new Error("Impossible de créer le match.");
  }

  logger.info(`[${MODULE_NAME}] Match créé - code: ${code}, id: ${matchId}`);
  return JSON.stringify({ code, match_id: matchId });
};

// ─── RPC: join_match_by_label ─────────────────────────────────────────────────

const rpcJoinMatchByLabel: nkruntime.RpcFunction = (_ctx, logger, nk, payload): string => {
  if (!payload || payload.trim() === "") {
    throw new Error("Payload requis: {\"code\": \"XXXXXX\"}");
  }

  let data: { code?: string };
  try {
    data = JSON.parse(payload);
  } catch (_e) {
    throw new Error("JSON invalide.");
  }

  if (!data.code || data.code.length !== CODE_LENGTH) {
    throw new Error(`Code invalide. Attendu: ${CODE_LENGTH} caractères.`);
  }

  const code = data.code.toUpperCase().trim();

  // Cherche les matchs autoritaires avec ce label exact
  // minSize=0 : inclut les matchs fraîchement créés sans joueurs
  const matches = nk.matchList(5, true, code, 0, MAX_PLAYERS, "");

  if (!matches || matches.length === 0) {
    logger.warn(`[${MODULE_NAME}] Aucun match pour le code: ${code}`);
    throw new Error(`Salon introuvable pour le code: ${code}`);
  }

  // Prend le match avec le moins de joueurs (load balancing basique)
  const match = matches.reduce((prev, cur) =>
    (cur.size ?? 0) < (prev.size ?? 0) ? cur : prev
  );

  logger.info(`[${MODULE_NAME}] Match trouvé - code: ${code}, id: ${match.matchId}, joueurs: ${match.size}`);
  return JSON.stringify({ match_id: match.matchId });
};

// ─── Module Init ──────────────────────────────────────────────────────────────

function InitModule(
  _ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): Error | void {
  initializer.registerMatch<MatchState>(MODULE_NAME, {
    matchInit,
    matchJoinAttempt,
    matchJoin,
    matchLeave,
    matchLoop,
    matchTerminate,
    matchSignal,
  });

  initializer.registerRpc("create_private_match", rpcCreatePrivateMatch);
  initializer.registerRpc("join_match_by_label", rpcJoinMatchByLabel);

  logger.info("[power_quest] Module initialisé avec succès.");
}
