// Knowledge Assistant front end: Cognito hosted login (authorization code + PKCE) and a chat
// view over the POST /query API. Plain JavaScript, no build step.
//
// Security notes:
// - All API text is inserted with textContent, never innerHTML, so answers cannot inject markup.
// - Tokens live in sessionStorage, which is cleared when the tab closes.
"use strict";

const config = window.RAG_CONFIG;
const TOKEN_KEY = "rag.idToken";
const PKCE_KEY = "rag.pkce";

const $ = (id) => document.getElementById(id);

// ------------------------------------------------------------------ auth helpers

function base64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function randomString() {
  return base64url(crypto.getRandomValues(new Uint8Array(32)));
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return base64url(new Uint8Array(digest));
}

function decodeJwt(token) {
  const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  const bytes = Uint8Array.from(atob(payload), (c) => c.charCodeAt(0));
  return JSON.parse(new TextDecoder().decode(bytes));
}

function currentToken() {
  const token = sessionStorage.getItem(TOKEN_KEY);
  if (!token) return null;
  try {
    const { exp } = decodeJwt(token);
    if (exp * 1000 > Date.now() + 30_000) return token;
  } catch {
    // fall through: malformed token
  }
  sessionStorage.removeItem(TOKEN_KEY);
  return null;
}

async function signIn() {
  const verifier = randomString();
  const state = randomString();
  sessionStorage.setItem(PKCE_KEY, JSON.stringify({ verifier, state }));
  const params = new URLSearchParams({
    response_type: "code",
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    scope: "openid email",
    state,
    code_challenge_method: "S256",
    code_challenge: await sha256(verifier),
  });
  window.location.assign(`${config.cognitoDomain}/oauth2/authorize?${params}`);
}

function signOut() {
  sessionStorage.removeItem(TOKEN_KEY);
  const params = new URLSearchParams({ client_id: config.clientId, logout_uri: config.redirectUri });
  window.location.assign(`${config.cognitoDomain}/logout?${params}`);
}

// Back from the hosted login page with ?code=...&state=...: exchange the code for tokens.
async function completeSignIn() {
  const url = new URL(window.location.href);
  const code = url.searchParams.get("code");
  if (!code) return;

  const saved = JSON.parse(sessionStorage.getItem(PKCE_KEY) || "{}");
  sessionStorage.removeItem(PKCE_KEY);
  window.history.replaceState({}, "", config.redirectUri);
  if (!saved.verifier || saved.state !== url.searchParams.get("state")) {
    throw new Error("Sign-in could not be verified. Please try again.");
  }

  const response = await fetch(`${config.cognitoDomain}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      client_id: config.clientId,
      code,
      redirect_uri: config.redirectUri,
      code_verifier: saved.verifier,
    }),
  });
  if (!response.ok) throw new Error("Sign-in failed. Please try again.");
  const tokens = await response.json();
  sessionStorage.setItem(TOKEN_KEY, tokens.id_token);
}

// ------------------------------------------------------------------ chat

function addMessage(kind, text) {
  const el = document.createElement("div");
  el.className = `message ${kind}`;
  el.textContent = text;
  $("messages").appendChild(el);
  el.scrollIntoView({ behavior: "smooth", block: "end" });
  return el;
}

function renderAnswer(data) {
  const node = $("answer-template").content.firstElementChild.cloneNode(true);
  node.querySelector(".text").textContent = data.answer;

  if (data.blocked) {
    const badge = node.querySelector(".badge");
    badge.textContent = "Blocked by safety policy";
    badge.hidden = false;
  }

  const citations = data.citations || [];
  if (citations.length) {
    const details = node.querySelector(".citations");
    details.hidden = false;
    details.querySelector("summary").textContent = `${citations.length} source${citations.length > 1 ? "s" : ""} cited`;
    const list = details.querySelector("ol");
    for (const cite of citations) {
      const item = document.createElement("li");
      const doc = document.createElement("div");
      doc.className = "doc";
      doc.textContent = `${cite.document_key} (part ${cite.chunk_index + 1})`;
      const quote = document.createElement("blockquote");
      quote.textContent = cite.cited_text;
      item.append(doc, quote);
      list.appendChild(item);
    }
  } else if (!data.blocked && (data.sources || []).length === 0) {
    node.querySelector(".meta").textContent = "No matching documents were found.";
  }

  if (data.model) {
    const meta = node.querySelector(".meta");
    meta.textContent = [meta.textContent, `Answered by ${data.model.replace(/^anthropic\./, "")}`].filter(Boolean).join(" · ");
  }

  $("messages").appendChild(node);
  node.scrollIntoView({ behavior: "smooth", block: "end" });
}

function showQuota(remaining) {
  $("quota").textContent =
    remaining === null || remaining === undefined ? "" : `${remaining} question${remaining === 1 ? "" : "s"} left today on this account`;
}

async function ask(question) {
  const token = currentToken();
  if (!token) return signIn();

  $("suggestions")?.remove();
  addMessage("user", question);
  const pending = addMessage("assistant pending", "Searching the documents...");
  $("send").disabled = true;

  try {
    const response = await fetch(config.apiUrl, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ question }),
    });
    pending.remove();

    if (response.status === 401) {
      sessionStorage.removeItem(TOKEN_KEY);
      addMessage("error", "Your session expired. Sign in again to continue.");
      return;
    }
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      addMessage("error", data.error || data.message || `Request failed (HTTP ${response.status}).`);
      return;
    }
    renderAnswer(data);
    showQuota(data.remaining_questions_today);
  } catch {
    pending.remove();
    addMessage("error", "Could not reach the assistant. Check your connection and try again.");
  } finally {
    $("send").disabled = false;
  }
}

// ------------------------------------------------------------------ page setup

function showSignedOut() {
  $("welcome").hidden = false;
  if (config.demoHint) {
    $("demo-box").hidden = false;
    $("demo-hint").textContent = config.demoHint;
    $("demo-limit").textContent = config.demoDailyLimit
      ? `The demo account is limited to ${config.demoDailyLimit} questions per day, shared by all visitors.`
      : "";
  }
}

function showSignedIn(token) {
  $("chat").hidden = false;
  $("account").hidden = false;
  $("user-email").textContent = decodeJwt(token).email || "";
  $("question").focus();
}

async function init() {
  $("sign-in").addEventListener("click", signIn);
  $("sign-out").addEventListener("click", signOut);

  $("composer").addEventListener("submit", (event) => {
    event.preventDefault();
    const question = $("question").value.trim();
    if (!question) return;
    $("question").value = "";
    ask(question);
  });
  $("question").addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      $("composer").requestSubmit();
    }
  });
  for (const chip of document.querySelectorAll(".chip")) {
    chip.addEventListener("click", () => ask(chip.textContent));
  }

  try {
    await completeSignIn();
  } catch (error) {
    showSignedOut();
    const notice = document.createElement("p");
    notice.className = "message error";
    notice.textContent = error.message;
    $("welcome").prepend(notice);
    return;
  }

  const token = currentToken();
  if (token) showSignedIn(token);
  else showSignedOut();
}

init();
