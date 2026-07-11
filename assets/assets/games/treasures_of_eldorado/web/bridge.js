/**
 * Treasures of El Dorado host bridge for Flutter InAppWebView.
 * Boots official bundle.js when present; forwards SEND_REQUEST to Flutter.
 */
(function () {
  const statusEl = () => document.getElementById("status");
  const setStatus = (msg) => {
    const el = statusEl();
    if (el) el.textContent = msg;
    postToFlutter({ type: "status", message: String(msg) });
  };

  const hub = Object.create(null);
  window.PubSub = {
    subscribe(event, cb) {
      if (event == null) return { unsubscribe() {} };
      (hub[event] || (hub[event] = [])).push(cb);
      return {
        unsubscribe() {
          hub[event] = (hub[event] || []).filter((x) => x !== cb);
        },
      };
    },
    publish(event, data) {
      if (event == null) return;
      (hub[event] || []).forEach((cb) => {
        try {
          cb(event, data);
        } catch (e) {
          console.error(e);
        }
      });
    },
    publishWithOrigin(event, data) {
      this.publish(event, data);
    },
  };

  const EVENT_NAMES = [
    "AUTOPLAY_CLOSED", "AUTOPLAY_END", "AUTOPLAY_START", "AUTOPLAY_STOP", "AUTOPLAY_UPDATE",
    "BALANCE_UPDATED", "BONUS_END", "BONUS_START", "CLOSE_GAME_POPUP",
    "DISABLE_AUTOSPIN", "DISABLE_SPIN", "DISABLE_STAKE", "DISABLE_WRAPPER_MENU_BUTTON",
    "DYNAMIC_HELP_CONTENT", "ENABLE_AUTOSPIN", "ENABLE_SPIN", "ENABLE_STAKE",
    "FREEBET_END", "FREEBET_START",
    "GAMEPLAY_ENDED", "GAMEPLAY_ENDED_COMPLETED", "GAMEPLAY_STARTED", "GAMEPLAY_STARTED_COMPLETED",
    "GAME_INITIALISED", "GAME_IN_PROGRESS",
    "GET_CLIENT_DATA", "GET_CLIENT_DATA_PROCESSED", "GET_GAMEPLAY_DATA", "GET_GAMEPLAY_DATA_PROCESSED",
    "HIDE_PAYTABLE", "HIDE_WRAPPER_MENU_BUTTON", "HIDE_WRAPPER_UI",
    "HOST_REQUEST_UPDATE_BALANCE", "INITIALISE_GAME",
    "LOADING_COMPLETED", "LOADING_PROGRESS", "LOADING_STARTED", "MENU_CLOSED",
    "NETWORK_ERROR", "PERFORM_SPIN", "REQUEST_ERROR", "REQUEST_PROCESSED", "REQUEST_WRAPPER_REFRESH",
    "RESIZE", "RESULT_SHOWN", "RESULT_SHOWN_PROCESSED", "RESUME_GAME",
    "SAVE_CLIENT_DATA", "SAVE_CLIENT_DATA_PROCESSED", "SAVE_GAMEPLAY_DATA", "SAVE_GAMEPLAY_DATA_PROCESSED",
    "SEND_REQUEST",
    "SET_GAME_STAKE", "SET_SOUND_OFF", "SET_SOUND_ON", "SET_STAKE", "SET_TURBO_OFF", "SET_TURBO_ON",
    "SHOW_AUTOPLAY", "SHOW_GAME", "SHOW_GAME_POPUP", "SHOW_MENU", "SHOW_PAYTABLE",
    "SHOW_WRAPPER_MENU_BUTTON", "SHOW_WRAPPER_UI",
    "SOUND_OFF", "SOUND_ON", "SPIN_DELAY_START", "SPLASH_HIDDEN", "SUSPEND_GAME",
    "TURBO_OFF", "TURBO_ON", "UPDATE_BALANCE", "UPDATE_WINNINGS",
    "WRAPPER_MENU_CLOSED", "WRAPPER_MENU_SHOWN", "WRAPPER_READY",
  ];
  const Events = {};
  for (const n of EVENT_NAMES) Events[n] = n;

  let launch = {
    token: "demo",
    user: "0",
    currency: "USD",
    language: "en",
    game: "treasuresofeldoradortp94",
    gameBaseUrl: null,
  };
  let definitions = null;
  let pendingReply = null;
  let bundleLoaded = false;

  function postToFlutter(payload) {
    const raw = JSON.stringify(payload);
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler("TreasuresOfEldoradoHost", raw);
        return;
      }
    } catch (e) {
      console.warn(e);
    }
    console.log("[TreasuresOfEldoradoHost]", payload);
  }

  window.__eldoradoHostReply = function (replyRaw) {
    let reply = replyRaw;
    if (typeof replyRaw === "string") {
      try {
        reply = JSON.parse(replyRaw);
      } catch (_) {
        reply = { ok: false, error: "bad reply" };
      }
    }
    if (pendingReply) {
      const resolve = pendingReply;
      pendingReply = null;
      resolve(reply);
    }
  };

  function askFlutter(payload) {
    return new Promise((resolve) => {
      pendingReply = resolve;
      postToFlutter(payload);
      setTimeout(() => {
        if (pendingReply === resolve) {
          pendingReply = null;
          resolve({ ok: false, error: "timeout" });
        }
      }, 30000);
    });
  }

  function gamePath() {
    // Official client uses `/${Playzido.getGamePath()}` 閳?    // Bundled layout: ../game/ next to web/
    if (launch.gameBaseUrl) {
      const b = launch.gameBaseUrl.endsWith("/")
        ? launch.gameBaseUrl
        : launch.gameBaseUrl + "/";
      return b.replace(/^https?:\/\/[^/]+\//, "");
    }
    return "game/treasuresofeldoradortp94/";
  }

  window.Playzido = {
    Events,
    Messages: {},
    config: {
      getFromState(path, fallback) {
        const map = {
          allowAutoplay: true,
          allowBuyoutFeature: true,
          allowSmallWinCelebration: true,
          allowSpinStop: true,
          "menu-options.turbo": true,
          demoMode: true,
        };
        if (typeof path === "string" && path in map) return map[path];
        if (Array.isArray(path)) {
          const key = path.join(".");
          if (key in map) return map[key];
        }
        return fallback !== undefined ? fallback : true;
      },
      getGameParam(key) {
        if (key === "token") return launch.token;
        return null;
      },
    },
    versions() {
      return { wrapper: "kessgame-flutter", game: "1.0.4", engine: "1.0.4", oga: "1.0.0" };
    },
    keyboardEvents: {
      bind() {
        return this;
      },
      unbind() {
        return this;
      },
    },
    getGamePath() {
      // Relative to this HTML when using bundled assets: ../game/
      // Absolute CDN path when gameBaseUrl is set.
      if (launch.gameBaseUrl) {
        const b = launch.gameBaseUrl.endsWith("/")
          ? launch.gameBaseUrl
          : launch.gameBaseUrl + "/";
        try {
          const u = new URL(b);
          return u.pathname.replace(/^\//, "");
        } catch (_) {
          return "game/treasuresofeldoradortp94/";
        }
      }
      return "../game/";
    },
    getGameName() {
      return launch.game;
    },
    getLanguageCode() {
      return launch.language || "en";
    },
    getPlayMode() {
      return "demoplay";
    },
    getMinimumTimeBetweenSpinRequests() {
      return 0;
    },
    getSize() {
      return { width: window.innerWidth, height: window.innerHeight };
    },
    formatCurrency(v) {
      try {
        return new Intl.NumberFormat("en", {
          style: "currency",
          currency: launch.currency || "USD",
        }).format(Number(v) || 0);
      } catch (_) {
        return String(v ?? 0);
      }
    },
    subscribe(event, cb) {
      return PubSub.subscribe(event, cb);
    },
    publish(event, data) {
      return PubSub.publish(event, data);
    },
  };

  PubSub.subscribe(Events.INITIALISE_GAME, () => {
    setTimeout(() => {
      PubSub.publish(Events.GAME_INITIALISED, {
        recover: false,
        definitions: definitions || { engine: {}, oga: {} },
      });
    }, 50);
  });

  PubSub.subscribe(Events.SHOW_GAME_POPUP, (_e, data) => {
    setTimeout(() => {
      const btn = data && data.buttons && data.buttons[0];
      if (btn && typeof btn.action === "function") {
        try {
          btn.action();
        } catch (e) {
          console.warn(e);
        }
      }
      PubSub.publish(Events.CLOSE_GAME_POPUP);
    }, 80);
  });

  PubSub.subscribe(Events.GET_CLIENT_DATA, () => {
    PubSub.publish(Events.GET_CLIENT_DATA_PROCESSED, {});
  });
  PubSub.subscribe(Events.GET_GAMEPLAY_DATA, () => {
    PubSub.publish(Events.GET_GAMEPLAY_DATA_PROCESSED, {});
  });

  PubSub.subscribe(Events.SEND_REQUEST, async (_e, payload) => {
    setStatus("RGS request閳?);
    const reply = await askFlutter({
      type: "send_request",
      payload: payload || {},
    });
    if (!reply || !reply.ok || !reply.result) {
      setStatus("RGS error: " + ((reply && reply.error) || "failed"));
      PubSub.publish(Events.NETWORK_ERROR, {
        methodName: "sendRequest",
        error: (reply && reply.error) || "failed",
      });
      return;
    }
    PubSub.publish(Events.REQUEST_PROCESSED, reply.result);
    setStatus("Spin OK");
  });

  PubSub.subscribe(Events.LOADING_COMPLETED, () => setStatus("Assets loaded"));

  function resolveBundleSrc() {
    if (launch.gameBaseUrl) {
      const b = launch.gameBaseUrl.endsWith("/")
        ? launch.gameBaseUrl
        : launch.gameBaseUrl + "/";
      return b + "js/bundle.js";
    }
    return "../game/js/bundle.js";
  }

  function loadBundle() {
    if (bundleLoaded) return;
    const src = resolveBundleSrc();
    const s = document.createElement("script");
    s.src = src;
    s.onload = () => {
      bundleLoaded = true;
      setStatus("Official bundle loaded");
      setTimeout(() => PubSub.publish(Events.WRAPPER_READY), 200);
    };
    s.onerror = () => {
      const miss = document.getElementById("missing");
      if (miss) miss.style.display = "flex";
      setStatus("Missing official bundle.js");
    };
    document.body.appendChild(s);
  }

  window.__eldoradoBootstrap = function (msg) {
    try {
      const session = (msg && msg.session) || {};
      const L = session.launch || {};
      launch = {
        token: L.token || launch.token,
        user: L.user || launch.user,
        currency: L.currency || launch.currency,
        language: L.language || launch.language,
        game: L.game || launch.game,
        gameBaseUrl: L.gameBaseUrl || null,
      };
      definitions = session.definitions || null;
      setStatus(
        "Boot 璺?bal " +
          (session.balance != null ? session.balance : "?") +
          " " +
          (session.currency || "")
      );
      loadBundle();
    } catch (e) {
      console.error(e);
      setStatus(String(e));
    }
  };

  window.addEventListener("resize", () => {
    PubSub.publish(Events.RESIZE, {
      width: window.innerWidth,
      height: window.innerHeight,
    });
  });

  setStatus("Bridge ready 璺?waiting bootstrap");
  // Allow standalone browser debug without Flutter
  if (!window.flutter_inappwebview) {
    window.__eldoradoBootstrap({
      type: "bootstrap",
      session: {
        balance: 1000,
        currency: "USD",
        definitions: null,
        launch: launch,
      },
    });
  }
})();
