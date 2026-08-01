# frozen_string_literal: true

require "json"
require "mudbase_sdk"

module Mudbase
  # `MudbaseSDK::ApiError#code`/`#response_body` carry the HTTP status and raw JSON body, but
  # `#message` mashes them into one multi-line string meant for logs, not end users. This
  # extracts the platform's own `{"error": "..."}` message (or a generic fallback) for display
  # in a flash banner, and separately exposes the status code for branching (e.g. 401 refresh).
  # Ported verbatim from the sibling ../../mudbase-showcase-social/ruby/lib/mudbase/errors.rb
  # (itself ported from the kanban/ecommerce ports).
  class ApiFailure
    attr_reader :status, :friendly_message

    def initialize(api_error)
      @status = api_error.respond_to?(:code) ? api_error.code : nil
      @friendly_message = extract_message(api_error) || "Something went wrong talking to Mudbase. Please try again."
    end

    def self.from(api_error)
      new(api_error)
    end

    private

    def extract_message(api_error)
      body = api_error.respond_to?(:response_body) ? api_error.response_body : nil
      return nil if body.nil? || body.empty?

      parsed = JSON.parse(body)
      parsed["error"] || parsed["message"]
    rescue JSON::ParserError
      nil
    end
  end
end
