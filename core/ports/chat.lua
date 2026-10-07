-- Any OpenRouter, Cerebras or MiniMax chat model behind Mercury's chat shape, so a model can take
-- Mercury's place as the writer without the solver knowing.
--
--   local kimi = require("ports.chat").new(host, { key = k, model = "moonshotai/kimi-k2-thinking" })
--   local oss = require("ports.chat").new(host, { key = k, service = "cerebras", model = "gpt-oss-120b" })
--   opts.timeout (seconds a call may take, 180 by default) and opts.once (a failure is not tried again): for a
--   call worth having only soon, such as a world model's foresight
--   local own = require("ports.chat").new(host, { key = k, service = "openai", url = ".../v1/chat/completions",
--                                                 model = "qwen-agent" })   any OpenAI-compatible server
--   local voice = require("ports.chat").new(host, { key = k, model = "deepseek/deepseek-v4.1-flash", thinking = false,
--                                                   sort = "latency" })
--   m:chat{ system, user | messages, max_tokens, json, reasoning_effort, on_text, tools, tool_choice, temperature,
--           thinking }   thinking = false for this call alone
--     -> text, record
--
-- on_text(piece, so_far), when given, asks for the reply as a stream (ports/stream.lua) and hears it as it comes,
-- so its first words can be shown before the last is written; the whole reply is still returned.
--
-- messages, when given, are the conversation as real turns ({ role = "user" | "assistant", content }) after the
-- system text, in place of one user message (with no system, messages are the whole conversation, its own system
-- turn first, as Mercury takes them). tools and tool_choice ask for tool calls, as Mercury's do: the calls come
-- back in record.tool_calls, and a reply of calls alone is an answer; opts.tool_choice, when given, is sent in
-- place of every request's (Qwen 3.8 thinking refuses "required", 2026-10-02, so a caller gives it "auto").
-- thinking = false (OpenRouter) asks the model not to reason before it answers, and reserves no reasoning tokens: for a spoken reply, where the first words must come at once.
--
-- MiniMax's own API (service = "minimax", model "MiniMax-M3"): its thinking is asked to come apart from the answer
-- (reasoning_split; without it the answer carries it in <think> tags), and thinking = false is MiniMax's
-- thinking { type = "disabled" } (M3 takes it; MiniMax-M3.1-Flash-Preview refuses it with a 400). A tool turn sent
-- back keeps its reasoning_content, as MiniMax asks.
-- An OpenAI-compatible server (service = "openai") is sent req.reasoning_effort as asked: Ollama's Qwen3.5 answers
-- only with "none", and otherwise spends every token thinking.
-- A reply that ends at its token limit with nothing said spent the limit reasoning: its error says how many tokens
-- went to reasoning, so a caller raises max_tokens or turns thinking off rather than trying the same call again.
--
-- OpenRouter takes req.reasoning_effort as reasoning.effort. Cerebras (owner, 2026-09-28) takes reasoning_effort as asked (Mercury's low | medium | high) and reports
-- no cost, so the record's cost comes from its listed prices per million tokens (M.prices).
--
-- A thinking model spends tokens on reasoning before it answers, so the
-- request allows opts.reasoning_tokens (default 8000) on top of max_tokens.
-- The record carries OpenRouter's own cost and the token counts in Mercury's
-- shape { prompt, cached, completion }; it never holds the key.
local call = require("ports.call")
local stream = require("ports.stream")

local M = {}
local Chat = {}
Chat.__index = Chat

M.url = "https://openrouter.ai/api/v1/chat/completions"
M.urls = { openrouter = M.url, cerebras = "https://api.cerebras.ai/v1/chat/completions",
  minimax = "https://api.minimax.io/v1/chat/completions" }
M.reasoning_tokens = 8000
-- USD per million tokens, input and output, as Cerebras lists them (2026-09-28).
M.prices = { ["gpt-oss-120b"] = { 0.35, 0.75 }, ["qwen-3.8-27b"] = { 0.99, 1.49 },
  ["meta-llama/llama-4-scout-17b-16e-instruct"] = { 0.11, 0.34 } }

function M.cost(model, u)
  local p = M.prices[model]
  if not p or not u.prompt_tokens then return nil end
  return (u.prompt_tokens * p[1] + (u.completion_tokens or 0) * p[2]) / 1e6
end

function M.new(host, opts)
  assert(host and host.fetch, "chat needs a host with fetch")
  assert(opts and opts.key, "chat needs a key")
  assert(opts.model, "chat needs a model")
  local service = opts.service or "openrouter"
  assert(M.urls[service] or (service == "openai" and opts.url), "chat knows no service " .. tostring(service)
    .. (service == "openai" and " without a url" or ""))
  return setmetatable({ host = host, key = opts.key, model = opts.model, service = service,
    url = opts.url or M.urls[service],
    reasoning_tokens = opts.reasoning_tokens or (opts.thinking == false and 0 or M.reasoning_tokens), sort = opts.sort,
    thinking = opts.thinking, tool_choice = opts.tool_choice, timeout = opts.timeout or 180, once = opts.once }, Chat)
end

function Chat:chat(req)
  local payload = {
    model = self.model, max_tokens = req.max_tokens and req.max_tokens + self.reasoning_tokens,
    messages = { req.system and { role = "system", content = req.system } or nil },
    temperature = req.temperature,
  }
  if req.messages then
    -- a turn keeps its tool calls (assistant) and the call it answers (tool), so a model can look something up and
    -- go on from what it found
    for _, m in ipairs(req.messages) do
      payload.messages[#payload.messages + 1] = { role = m.role, content = m.content, tool_calls = m.tool_calls,
        tool_call_id = m.tool_call_id, reasoning_content = m.reasoning_content }
    end
  else
    payload.messages[2] = { role = "user", content = req.user }
  end
  if self.service == "openrouter" then
    payload.usage = { include = true }
    -- req.sort, when given, overrides the port's provider order for this call: a retry after a provider timed out
    -- asks by latency (studio s3: one set_prop waited 37 minutes on a provider that never answered)
    local sort = req.sort or self.sort
    if sort then payload.provider = { sort = sort } end
    -- req.thinking, when given, overrides the port's for this call: a fill that should come at once beside a
    -- thought that should not
    local thinking = req.thinking
    if thinking == nil then thinking = self.thinking end
    if thinking == false then
      payload.reasoning = { enabled = false }
    elseif req.reasoning_effort then
      -- some endpoints refuse reasoning off (GLM 5.3 Flash: "Reasoning is mandatory"); low effort is how they go fast
      payload.reasoning = { effort = req.reasoning_effort }
    end
  elseif self.service == "openai" then
    -- a model the host serves itself (vLLM, SGLang): Qwen's thinking is switched in its chat template
    local thinking = req.thinking
    if thinking == nil then thinking = self.thinking end
    if thinking ~= nil then payload.chat_template_kwargs = { enable_thinking = thinking } end
    payload.reasoning_effort = req.reasoning_effort
  elseif self.service == "minimax" then
    local thinking = req.thinking
    if thinking == nil then thinking = self.thinking end
    if thinking == false then payload.thinking = { type = "disabled" } end
    payload.reasoning_split = true
    payload.reasoning_effort = req.reasoning_effort
  else
    payload.reasoning_effort = req.reasoning_effort
  end
  if req.json then payload.response_format = { type = "json_object" } end
  if req.tools then payload.tools, payload.tool_choice = req.tools, self.tool_choice or req.tool_choice end
  local body, record
  if req.on_text then
    payload.stream = true
    local r = stream.reader(req.on_text)
    _, record = call.post(self.host, self.service, self.url, self.key, payload, self.timeout, function(c) r:feed(c) end,
      self.once)
    body = { model = r.model, usage = r.usage, choices = { { message = { content = r.text }, finish_reason = r.finish } } }
  else
    body, record = call.post(self.host, self.service, self.url, self.key, payload, self.timeout, nil, self.once)
  end
  local u = body.usage or {}
  local details = u.prompt_tokens_details or {}
  record.model = body.model or self.model
  record.provider = body.provider
  record.cost = u.cost or M.cost(self.model, u)
  record.usage = { prompt = u.prompt_tokens, cached = details.cached_tokens or 0, completion = u.completion_tokens }
  local choice = body.choices and body.choices[1]
  local text = choice and choice.message and choice.message.content
  if req.tools then
    record.tool_calls = choice and choice.message and choice.message.tool_calls or {}
    if #record.tool_calls > 0 then return type(text) == "string" and text or "", record end
  end
  if type(text) ~= "string" or text == "" then
    local finish = choice and choice.finish_reason
    local thought = (u.completion_tokens_details or {}).reasoning_tokens
    if finish == "length" and thought then
      error(("%s spent its limit, %d tokens reasoning, and said nothing: raise max_tokens or ask with thinking = false")
        :format(record.model, thought), 0)
    end
    error(("%s gave no answer (finish %s)"):format(record.model, tostring(choice and choice.finish_reason)), 0)
  end
  return text, record
end

return M
