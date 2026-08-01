# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "../mudbase/config"

module Llm
  # Raised when the LLM completion call can't be made or returns nothing usable.
  class LlmError < StandardError; end

  # The one place in this codebase that calls a third-party LLM API - a plain `Net::HTTP`
  # request against Anthropic's Messages API (no SDK gem needed for one endpoint). This mirrors
  # exactly why the reference Next.js app's `src/lib/server/llm.ts` exists as a tiny, isolated
  # module: see plan/build-plan.md "Ask AI architecture" for the two verified platform
  # constraints that force this call to happen somewhere with a real outbound network stack
  # rather than inside the Mudbase Function itself (whose `isolated-vm` sandbox has no `fetch`,
  # no `http`/`https` module, and no way to reach any external host at all). This Sinatra app IS
  # that "somewhere" - being fully server-rendered, `ANTHROPIC_API_KEY` never leaves this
  # process; it is read straight from the environment and only ever attached as an outbound
  # request header to `api.anthropic.com`, never rendered into a page or logged.
  module AnthropicClient
    API_URL = "https://api.anthropic.com/v1/messages"
    ANTHROPIC_VERSION = "2023-06-01"
    DEFAULT_MODEL = "claude-opus-5"
    MAX_TOKENS = 1024

    SYSTEM_PROMPT = <<~PROMPT.strip
      You are a support assistant for a documentation knowledge base. Answer the user's
      question using ONLY the document excerpts provided below - never your own outside knowledge. If the
      excerpts do not contain enough information to answer, say so plainly rather than guessing. Keep the
      answer concise (a few sentences to a short paragraph). When you use a fact from an excerpt, mention
      which document it came from by its title.
    PROMPT

    # @param question [String]
    # @param context_block [String] the Mudbase Function's assembled, grounded excerpt block.
    # @return [String] the model's answer text.
    # @raise [LlmError] if the key is unconfigured, the request fails, or the model returns no
    #   usable text - never a fabricated answer.
    def self.generate_grounded_answer!(question:, context_block:)
      api_key = Mudbase::Config.anthropic_api_key
      if api_key.nil? || api_key.empty?
        raise LlmError,
          "ANTHROPIC_API_KEY is not configured. This is a server-only env var (see README.md " \
          '"LLM setup" and .env.example) - the developer running this app must supply their own key.'
      end

      user_content = if context_block.to_s.strip.empty?
        "Question: #{question}\n\n(No document excerpts were retrieved - say you don't have enough information in the knowledge base to answer.)"
      else
        "Question: #{question}\n\nDocument excerpts:\n#{context_block}"
      end

      body = {
        model: Mudbase::Config.llm_model,
        max_tokens: MAX_TOKENS,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: user_content }],
      }

      response = post(api_key, body)
      parsed = parse_json(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        detail = parsed.is_a?(Hash) ? parsed.dig("error", "message") : nil
        raise LlmError, "Anthropic API request failed (#{response.code}): #{detail || "unknown error"}"
      end

      text_block = (parsed["content"] || []).find { |block| block["type"] == "text" }
      if text_block.nil?
        raise LlmError, "The model declined to answer this question." if parsed["stop_reason"] == "refusal"

        raise LlmError, "The model returned no text content"
      end

      text_block["text"]
    end

    def self.post(api_key, body)
      uri = URI.parse(API_URL)
      request = Net::HTTP::Post.new(uri)
      request["x-api-key"] = api_key
      request["anthropic-version"] = ANTHROPIC_VERSION
      request["content-type"] = "application/json"
      request.body = JSON.generate(body)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 60
      http.request(request)
    rescue StandardError => e
      raise LlmError, "Network error calling the Anthropic API: #{e.message}"
    end
    private_class_method :post

    def self.parse_json(text)
      return nil if text.nil? || text.empty?

      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end
    private_class_method :parse_json
  end
end
