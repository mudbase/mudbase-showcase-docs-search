# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "config"

module Mudbase
  # Raised for any failure invoking or polling the deployed `docsAskRetrieval` Mudbase Function.
  class FunctionError < StandardError; end

  # Invokes the deployed Mudbase Function (`docsAskRetrieval`) that ranks candidate documents by
  # keyword overlap and assembles a grounded context block. This is a plain `Net::HTTP` request,
  # not mediated by the generated `mudbase_sdk` - the Function's `/execute` and `/executions/:id`
  # routes authenticate via `X-API-Key` (an org-scoped `ak_...` key with `functions` permission),
  # a completely different auth scheme from the bearer-JWT flow every other Mudbase call in this
  # app uses, so there's nothing the SDK's `ApiClient`/`Configuration` machinery would buy here.
  #
  # See plan/build-plan.md "Ask AI architecture" for why this key must exist at all: a project
  # end-user JWT (what every signed-in customer and anonymous guest in this app carries) can only
  # ever satisfy `rbacCheck("functions","read")`, never the `"create"` action the `/execute`
  # route requires - only an org-scoped API key with elevated `functions` permissions can invoke
  # it. This key lives only as the server-only `MUDBASE_FUNCTIONS_API_KEY` env var, used
  # exclusively by this module, and (being a fully server-rendered Sinatra app) is never at risk
  # of reaching a browser the way a client-side secret would be.
  module FunctionClient
    POLL_INTERVAL_SECONDS = 0.6
    POLL_TIMEOUT_SECONDS = 20

    Result = Struct.new(:context_block, :citations, :used_count, keyword_init: true)

    # @param question [String]
    # @param candidates [Array<Hash>] `{ documentId:, title:, content:, tags: }` shortlist,
    #   already scored and truncated client-side (here: server-side, see lib/retrieval.rb).
    # @return [Result]
    # @raise [FunctionError] on any non-success execute/poll/timeout outcome.
    def self.invoke_retrieval(question:, candidates:)
      base_uri = URI.parse(Mudbase::Config.base_url)
      project_id = Mudbase::Config.project_id
      function_id = Mudbase::Config.function_id
      api_key = Mudbase::Config.functions_api_key

      execution_id = execute!(base_uri, project_id, function_id, api_key, question, candidates)
      poll_until_done!(base_uri, project_id, function_id, api_key, execution_id)
    end

    def self.execute!(base_uri, project_id, function_id, api_key, question, candidates)
      uri = base_uri.merge("/api/functions/projects/#{project_id}/functions/#{function_id}/execute")
      response = post_json(uri, api_key, { payload: { question: question, candidates: candidates } })
      body = parse_json(response.body)

      unless response.is_a?(Net::HTTPSuccess) && body.is_a?(Hash) && body["success"] && body["data"]
        raise FunctionError,
          "Mudbase Function execute request failed (#{response.code}): #{body.is_a?(Hash) ? body["error"] : "unknown error"}"
      end

      body.dig("data", "executionId") || raise(FunctionError, "Function execute response had no executionId")
    end
    private_class_method :execute!

    def self.poll_until_done!(base_uri, project_id, function_id, api_key, execution_id)
      uri = base_uri.merge("/api/functions/projects/#{project_id}/functions/#{function_id}/executions/#{execution_id}")
      deadline = monotonic_now + POLL_TIMEOUT_SECONDS

      while monotonic_now < deadline
        response = get_json(uri, api_key)
        body = parse_json(response.body)

        unless response.is_a?(Net::HTTPSuccess) && body.is_a?(Hash) && body["success"] && body["data"]
          raise FunctionError, "Mudbase Function execution poll failed (#{response.code})"
        end

        status = body.dig("data", "status")
        case status
        when "success"
          result = body.dig("data", "result")
          raise FunctionError, "Function execution succeeded but returned no result" unless result

          return Result.new(
            context_block: result["contextBlock"].to_s,
            citations: (result["citations"] || []).map { |c| { documentId: c["documentId"], title: c["title"] } },
            used_count: result["usedCount"].to_i,
          )
        when "failed", "timeout"
          raise FunctionError, "Mudbase Function execution #{status}: #{body.dig("data", "error") || "unknown error"}"
        end

        sleep POLL_INTERVAL_SECONDS
      end

      raise FunctionError, "Timed out waiting for the Mudbase Function execution to complete"
    end
    private_class_method :poll_until_done!

    def self.post_json(uri, api_key, payload)
      request = Net::HTTP::Post.new(uri)
      request["X-API-Key"] = api_key
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)
      perform(uri, request)
    end
    private_class_method :post_json

    def self.get_json(uri, api_key)
      request = Net::HTTP::Get.new(uri)
      request["X-API-Key"] = api_key
      perform(uri, request)
    end
    private_class_method :get_json

    def self.perform(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15
      http.request(request)
    rescue StandardError => e
      raise FunctionError, "Network error calling the Mudbase Function API: #{e.message}"
    end
    private_class_method :perform

    def self.parse_json(text)
      return nil if text.nil? || text.empty?

      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end
    private_class_method :parse_json

    def self.monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    private_class_method :monotonic_now
  end
end
