# frozen_string_literal: true

module Mudbase
  # Fails fast at boot with a clear message rather than surfacing a confusing
  # nil-related error deep inside a request handler later.
  class MissingEnvError < StandardError
    def initialize(name)
      super("Missing required environment variable: #{name}")
    end
  end

  module Config
    def self.require_env(name)
      value = ENV[name]
      raise MissingEnvError, name if value.nil? || value.empty?

      value
    end

    def self.base_url
      ENV.fetch("MUDBASE_URL", "https://cloud.mudbase.dev")
    end

    def self.project_id
      require_env("MUDBASE_PROJECT_ID")
    end

    def self.documents_collection_id
      require_env("DOCUMENTS_COLLECTION_ID")
    end

    def self.search_log_collection_id
      require_env("SEARCH_LOG_COLLECTION_ID")
    end

    # These three are only required once the Ask AI flow is actually exercised (see
    # `lib/mudbase/function_client.rb` and `lib/llm/anthropic_client.rb`) rather than at boot,
    # so a developer who hasn't set up Ask AI yet can still browse/CRUD documents.
    def self.function_id
      require_env("MUDBASE_FUNCTION_ID")
    end

    def self.functions_api_key
      require_env("MUDBASE_FUNCTIONS_API_KEY")
    end

    # Deliberately NOT `require_env` - a missing key is a valid, honestly-documented runtime
    # state (see plan/build-plan.md "Known limitation"), not a boot-time misconfiguration. The
    # caller (`Llm::AnthropicClient.generate_grounded_answer!`) raises its own clear error when
    # this is blank, exactly where the reference Next.js app's `src/lib/server/llm.ts` does.
    def self.anthropic_api_key
      ENV["ANTHROPIC_API_KEY"]
    end

    def self.llm_model
      ENV.fetch("LLM_MODEL", "claude-opus-5")
    end

    def self.session_secret
      require_env("SESSION_SECRET")
    end
  end
end
