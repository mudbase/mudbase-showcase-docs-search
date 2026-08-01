# frozen_string_literal: true

require "dotenv/load"
require "uri"
require "sinatra/base"

require_relative "lib/mudbase/config"
require_relative "lib/mudbase/client_factory"
require_relative "lib/mudbase/errors"
require_relative "lib/mudbase/auth_service"
require_relative "lib/mudbase/documents_repo"
require_relative "lib/mudbase/search_log_repo"
require_relative "lib/mudbase/function_client"
require_relative "lib/llm/anthropic_client"
require_relative "lib/retrieval"
require_relative "lib/session_helpers"
require_relative "lib/view_helpers"

# Mudbase Showcase: Docs Search - an AI-powered knowledge-base search app built almost entirely
# on Mudbase (auth, database, a serverless Function for retrieval ranking), rendered server-side
# with Sinatra + ERB. This is the Ruby reimplementation of the reference Next.js app (see
# ../web): same Mudbase project, same two collections (`documents`/`search_log`), same single
# default `customer` role, same Ask AI architecture - different stack, following the Sinatra
# structure the sibling `mudbase-showcase-social`/`mudbase-showcase-kanban` ports established.
#
# Ask AI architecture (see plan/build-plan.md for the full source-cited rationale): a real,
# deployed Mudbase Function (`docsAskRetrieval`) does keyword-overlap retrieval ranking inside
# its network-isolated sandbox; the LLM completion call the sandbox is structurally incapable of
# making happens in this Sinatra app itself (lib/llm/anthropic_client.rb) - the smallest
# server-side surface available, and here that's simply "this app", since it is already fully
# server-rendered with a real network stack, unlike the reference Next.js app which needed one
# dedicated Route Handler carved out specifically for this.
class App < Sinatra::Base
  configure do
    set :root, File.dirname(__FILE__)
    set :views, File.join(settings.root, "views")
    set :public_folder, File.join(settings.root, "public")
    set :show_exceptions, false
    set :raise_errors, false

    is_production = ENV.fetch("RACK_ENV", "development") == "production"
    set :session_secret, Mudbase::Config.session_secret
    set :sessions, {
      key: "mudbase_showcase_docs_search.session",
      httponly: true,
      same_site: :lax,
      secure: is_production,
      expire_after: 60 * 60 * 12,
    }
  end

  configure :development do
    require "sinatra/reloader"
    register Sinatra::Reloader
  end

  helpers SessionHelpers
  helpers ViewHelpers

  before do
    @flash_notice = pop_flash_notice
    @flash_error = pop_flash_error
    @current_user = current_user
  end

  # `MudbaseSDK::ApiError` is what every generated API call raises on a non-2xx response
  # (invalid input, expired token, permission denial, etc.) - surfaced here as a flash-style
  # error banner instead of a raw 500, matching "never silently swallow errors" while still
  # giving the visitor something actionable.
  error MudbaseSDK::ApiError do
    failure = Mudbase::ApiFailure.from(env["sinatra.error"])
    if failure.status == 401
      clear_auth_session!
      flash_error("Your session expired - please sign in again.")
      redirect "/login"
    else
      flash_error(failure.friendly_message)
      redirect back_or("/")
    end
  end

  error Mudbase::MissingEnvError do
    content_type :text
    status 500
    "Server misconfigured: #{env['sinatra.error'].message}"
  end

  # Raised by `ensure_guest_session!`/`with_read_token` when even establishing a silent
  # anonymous session fails (Mudbase's own auth-endpoint rate limiting, or a real outage) - not
  # a `MudbaseSDK::ApiError` since `AuthService` normalizes it to this app-level error type.
  # Rendered directly (not redirected) since the failure can happen on `/` itself, where a
  # `redirect back_or("/")` could loop.
  error Mudbase::AuthError do
    @flash_error = "Couldn't reach Mudbase right now - please try again in a moment."
    erb :"errors/server_error", layout: :layout
  end

  not_found do
    erb :"errors/not_found", layout: :layout
  end

  error do
    logger.error(env["sinatra.error"]&.full_message) if env["sinatra.error"]
    erb :"errors/server_error", layout: :layout
  end

  helpers do
    def back_or(default_path)
      request.referrer && URI.parse(request.referrer).path != request.path ? request.referrer : default_path
    rescue URI::InvalidURIError
      default_path
    end

    # `true` only when the signed-in user's own id matches the document's `authorId` - the one
    # server-side ownership gate this app enforces on top of Mudbase's single-role full-CRUD
    # grant (see lib/mudbase/documents_repo.rb header comment), mirroring the reference web
    # app's `isOwner` check.
    def owner_of?(document)
      !!@current_user && @current_user[:id] == document[:authorId]
    end

    def actor_display_name
      "#{@current_user[:firstName]} #{@current_user[:lastName]}".strip
    end
  end
end

require_relative "app/routes/auth_routes"
require_relative "app/routes/documents_routes"
require_relative "app/routes/ask_routes"
