# frozen_string_literal: true

require "mudbase_sdk"
require_relative "config"

module Mudbase
  # Builds a fresh, request-scoped set of generated `MudbaseSDK::*Api` instances. Ported
  # verbatim from the sibling `mudbase-showcase-social`/`mudbase-showcase-kanban` ports - see
  # those files' header comments for the full rationale (process-wide singleton race avoidance).
  #
  # `MudbaseSDK::Configuration.default` / `MudbaseSDK::ApiClient.default` are process-wide
  # singletons - every generated API class defaults to them. Calling the documented
  # `MudbaseSDK.configure { |c| c.access_token = jwt }` per request would mutate that shared
  # singleton, a real race condition in a multi-threaded Puma server: request A could read
  # request B's bearer token if both configure the global default concurrently. Instead, every
  # call site in this app builds its own `Configuration.new` + `ApiClient.new(config)` and hands
  # the resulting api_client explicitly into `AuthenticationApi.new(api_client)` /
  # `DataApi.new(api_client)` - fully isolated per request, no shared mutable state.
  module ClientFactory
    # @param access_token [String, nil] Mudbase-issued JWT (real user or anonymous guest).
    #   Omit for public endpoints (login, register, anonymous session creation).
    # @return [MudbaseSDK::ApiClient]
    def self.api_client(access_token: nil)
      config = MudbaseSDK::Configuration.new
      config.host = URI.parse(Mudbase::Config.base_url).host
      config.scheme = URI.parse(Mudbase::Config.base_url).scheme
      config.access_token = access_token if access_token
      MudbaseSDK::ApiClient.new(config)
    end

    def self.auth_api(access_token: nil)
      MudbaseSDK::AuthenticationApi.new(api_client(access_token: access_token))
    end

    def self.multi_role_api(access_token: nil)
      MudbaseSDK::MultiRoleFeatureApi.new(api_client(access_token: access_token))
    end

    def self.data_api(access_token: nil)
      MudbaseSDK::DataApi.new(api_client(access_token: access_token))
    end

    # Forces the generated `_with_http_info` wrapper to deserialize the response body as a
    # plain Hash instead of a typed model. Needed for the same reason documented in the sibling
    # ports' `ClientFactory`: `DataListResponseDataInner`/similar collection-document models
    # only declare `_id`/`created_at`/`updated_at` (Collections are a dynamic per-project schema
    # the generator can't type) - every real field (`title`, `content`, `authorId`, `queryText`,
    # ...) would be silently dropped by typed deserialization. `LoginLocalUser200ResponseUser`/
    # `CreateAnonymousSession200ResponseUser` also still don't declare `customRole`/`isAnonymous`,
    # which this app's write-permission gating depends on.
    OBJECT_RESPONSE = { debug_return_type: "Object" }.freeze
  end
end
