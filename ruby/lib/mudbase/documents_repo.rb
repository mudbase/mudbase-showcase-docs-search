# frozen_string_literal: true

require "json"
require "mudbase_sdk"
require_relative "client_factory"
require_relative "config"

module Mudbase
  # Thin repository over `documents` - read granted to every role including the silent
  # anonymous guest (see SessionHelpers#with_read_token), create/update/delete require a real
  # signed-in "customer" account, with edit/delete additionally scoped to the document's own
  # `authorId` by this app's own routes (`app/routes/documents_routes.rb#require_owner!`) -
  # Mudbase's single default role grants full CRUD to any signed-in customer, so ownership isn't
  # enforced by the collection permission itself, only by this app, mirroring the reference web
  # app's `isOwner` check in `src/app/documents/[id]/page.tsx`. All calls force
  # `debug_return_type: "Object"` (see ClientFactory) so every real document field survives
  # typed deserialization.
  module DocumentsRepo
    # The generated SDK's `DataApi#list_data` client-side-validates `limit <= 100` - a real
    # platform-enforced ceiling (confirmed live by the sibling social/kanban ports' own builds),
    # not just a demo-scale choice. The library page and Ask AI's retrieval scoring both fetch
    # at most this many documents, matching the reference web app's own `limit: 100`/`limit: 200`
    # (this app uses 100, the SDK's own ceiling, for both).
    LIST_LIMIT = 100

    # @return [Array<Hash>] every document, newest first.
    def self.all(access_token:)
      opts = { sort: "-createdAt", limit: LIST_LIMIT }.merge(Mudbase::ClientFactory::OBJECT_RESPONSE)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).list_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.documents_collection_id,
        opts,
      )
      data[:data] || []
    end

    def self.find(access_token:, id:)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).get_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.documents_collection_id,
        id,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )
      data[:data]
    rescue MudbaseSDK::ApiError => e
      raise e unless Mudbase::ApiFailure.from(e).status == 404

      nil
    end

    def self.create!(access_token:, attributes:)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).create_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.documents_collection_id,
        attributes,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )
      data[:data]
    end

    def self.update!(access_token:, id:, attributes:)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).update_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.documents_collection_id,
        id,
        attributes,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )
      data[:data]
    end

    def self.delete!(access_token:, id:)
      Mudbase::ClientFactory.data_api(access_token: access_token).delete_data(
        Mudbase::Config.project_id,
        Mudbase::Config.documents_collection_id,
        id,
      )
    end
  end
end
