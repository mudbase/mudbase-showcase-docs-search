# frozen_string_literal: true

require "json"
require "mudbase_sdk"
require_relative "client_factory"
require_relative "config"

module Mudbase
  # Thin repository over `search_log` - an append-only record of every Ask AI question asked
  # (`queryText`, `resultCount`, and `userId`/`userName` when the asker is signed in - never a
  # placeholder value for `userId`, see `app/routes/ask_routes.rb`). Read by the "recent
  # searches" panel on `/ask`; never updated or deleted, so this module exposes no
  # `update!`/`delete!`.
  module SearchLogRepo
    # Recent-searches panel shows the 10 most recent entries, matching the reference web app's
    # `RecentSearches` component (`limit: 10`).
    RECENT_LIMIT = 10

    def self.recent(access_token:, limit: RECENT_LIMIT)
      opts = { sort: "-createdAt", limit: limit }.merge(Mudbase::ClientFactory::OBJECT_RESPONSE)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).list_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.search_log_collection_id,
        opts,
      )
      data[:data] || []
    end

    def self.create!(access_token:, attributes:)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).create_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.search_log_collection_id,
        attributes,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )
      data[:data]
    end
  end
end
