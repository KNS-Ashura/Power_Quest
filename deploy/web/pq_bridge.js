/**
 * Pont HTTP Nakama pour export Godot Web (fetch asynchrone, fiable).
 *
 * NOTE : le mécanisme principal est désormais `html/head_include` dans
 * export_presets.cfg, donc ce pont est injecté automatiquement dans le <head>
 * de CHAQUE export Godot — aucun fichier à copier, aucune édition manuelle.
 *
 * Ce fichier est conservé comme référence / secours uniquement.
 */
(function () {
	"use strict";
	window.PQ = window.PQ || {};
	window.PQ._r = window.PQ._r || {};

	window.PQ.send = function (id, url, method, headersJson, body) {
		var headers = {};
		try {
			headers = JSON.parse(headersJson || "{}");
		} catch (e) {
			headers = {};
		}
		var opts = {
			method: method || "POST",
			headers: headers,
			cache: "no-store",
			credentials: "omit",
		};
		if (method !== "GET" && body) {
			opts.body = body;
		}
		fetch(url, opts)
			.then(function (resp) {
				return resp.text().then(function (text) {
					window.PQ._r[id] = JSON.stringify({
						ok: resp.ok,
						status: resp.status,
						text: text,
					});
				});
			})
			.catch(function (err) {
				window.PQ._r[id] = JSON.stringify({
					ok: false,
					status: 0,
					text: "",
					error: String(err),
				});
			});
	};

	window.PQ.poll = function (id) {
		if (Object.prototype.hasOwnProperty.call(window.PQ._r, id)) {
			var value = window.PQ._r[id];
			delete window.PQ._r[id];
			return value;
		}
		return "";
	};
})();
