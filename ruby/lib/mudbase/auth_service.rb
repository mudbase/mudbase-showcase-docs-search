# frozen_string_literal: true

require "mudbase_sdk"
require_relative "client_factory"
require_relative "config"
require_relative "errors"

module Mudbase
  # Raised for any login/register/anonymous-session failure the caller should show to the end
  # user (or, for the anonymous case, log and treat as "public read unavailable right now").
  class AuthError < StandardError
    def initialize(message, requires_verification: false)
      super(message)
      @requires_verification = requires_verification
    end

    def requires_verification?
      @requires_verification
    end
  end

  # Normalizes the raw parsed-JSON auth response (token/refreshToken/expiresIn/user) into a
  # small value object the session helpers can store. Field names stay camelCase-symbol,
  # matching the wire format exactly (see ClientFactory::OBJECT_RESPONSE for why this app reads
  # raw hashes here instead of the generated typed models).
  AuthSession = Struct.new(:token, :refresh_token, :expires_in, :user, keyword_init: true) do
    def self.from_hash(data)
      new(
        token: data[:token],
        refresh_token: data[:refreshToken],
        expires_in: data[:expiresIn] || 3600,
        user: data[:user] || {},
      )
    end
  end

  # Wraps `MudbaseSDK::MultiRoleFeatureApi#register_with_role`,
  # `MudbaseSDK::AuthenticationApi#login_local_user`, `#create_anonymous_session`, and
  # `#refresh_token` - every auth flow this app needs. This project ships Mudbase's single
  # default starter application role - slug "customer" (verified live by the reference web
  # app's `src/lib/mudbase.ts`: signup against "user" 404s with "Role not found", signup against
  # "customer" succeeds) - so it's hardcoded here rather than exposed as a caller-supplied
  # parameter, plus a silent anonymous session for guests so public reads (the document library,
  # a document's full content, Ask AI) resolve without a login prompt - every collection read on
  # this backend requires *some* authenticated JWT, confirmed live (see plan/build-plan.md).
  module AuthService
    CUSTOMER_ROLE = "customer"

    def self.register_customer!(email:, password:, first_name:, last_name:, agreed_to_terms:)
      request = MudbaseSDK::RegisterWithRoleRequest.new(
        email: email,
        password: password,
        first_name: first_name,
        last_name: last_name,
        project_id: Mudbase::Config.project_id,
        agreed_to_terms: agreed_to_terms,
      )

      data, = Mudbase::ClientFactory.multi_role_api.register_with_role_with_http_info(
        CUSTOMER_ROLE,
        request,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )

      handle_auth_response(data)
    rescue MudbaseSDK::ApiError => e
      raise AuthError, Mudbase::ApiFailure.from(e).friendly_message
    end

    def self.login!(email:, password:)
      request = MudbaseSDK::LoginLocalUserRequest.new(
        email: email,
        password: password,
        project_id: Mudbase::Config.project_id,
      )

      data, = Mudbase::ClientFactory.auth_api.login_local_user_with_http_info(
        request,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )

      handle_auth_response(data)
    rescue MudbaseSDK::ApiError => e
      failure = Mudbase::ApiFailure.from(e)
      raise AuthError.new(failure.friendly_message, requires_verification: true) if failure.status == 403

      raise AuthError, failure.friendly_message
    end

    # Establishes a guest ("viewer" system role, no `customRole`) session purely so public reads
    # (the document library, a document's full content, Ask AI) resolve without ever prompting
    # a guest to sign in - mirrors the reference Next.js app's `MudbaseProvider`/`loginAnonymous`
    # bootstrap. No email/password involved; the platform mints a fresh anonymous identity per
    # call.
    def self.login_anonymous!
      request = MudbaseSDK::CreateAnonymousSessionRequest.new(project_id: Mudbase::Config.project_id)

      opts = { create_anonymous_session_request: request }.merge(Mudbase::ClientFactory::OBJECT_RESPONSE)
      data, = Mudbase::ClientFactory.auth_api.create_anonymous_session_with_http_info(opts)

      AuthSession.from_hash(data)
    rescue MudbaseSDK::ApiError => e
      raise AuthError, Mudbase::ApiFailure.from(e).friendly_message
    end

    # Exchanges a stored (single-use, rotate-on-use) refresh token for a fresh access/refresh
    # pair. Works for both a real user's refresh token and a guest anonymous session's refresh
    # token - the endpoint doesn't distinguish. No `user` in the response (the identity doesn't
    # change on refresh), so the returned `AuthSession#user` is left `nil`.
    def self.refresh!(refresh_token)
      request = MudbaseSDK::RefreshTokenRequest.new(refresh_token: refresh_token)
      data, = Mudbase::ClientFactory.auth_api.refresh_token_with_http_info(request)

      AuthSession.new(
        token: data.token,
        refresh_token: data.refresh_token,
        expires_in: data.expires_in || 3600,
        user: nil,
      )
    rescue MudbaseSDK::ApiError => e
      raise AuthError, Mudbase::ApiFailure.from(e).friendly_message
    end

    def self.logout!(access_token)
      Mudbase::ClientFactory.auth_api(access_token: access_token).logout_local_user
    rescue MudbaseSDK::ApiError
      # Best-effort: the local session cookie is cleared by the caller regardless, so a
      # failed server-side revoke (expired token, network blip) shouldn't block sign-out.
      nil
    end

    def self.handle_auth_response(data)
      if data[:token].nil? && data[:requireVerification]
        raise AuthError.new(
          "Account created - check your email to verify it, then sign in.",
          requires_verification: true,
        )
      end

      AuthSession.from_hash(data)
    end
    private_class_method :handle_auth_response
  end
end
