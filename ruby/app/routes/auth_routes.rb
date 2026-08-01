# frozen_string_literal: true

# Login/register/logout. Every self-signup goes through `AuthService.register_customer!`, which
# always requests the single `customer` role this project ships (see
# `lib/mudbase/auth_service.rb` header comment) - there is no role picker in this UI. A demo
# account (`docs.member.demo@gmail.com`) already exists and is provisioned out-of-band; `/login`
# ships a normal email+password form plus a "Sign in as demo member" one-click shortcut.
class App < Sinatra::Base
  EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/.freeze

  DEMO_ACCOUNT = { email: "docs.member.demo@gmail.com", password: "DemoTest123!" }.freeze

  get "/login" do
    redirect "/" if logged_in?
    @email = ""
    @demo_account = DEMO_ACCOUNT
    erb :"auth/login"
  end

  post "/login" do
    redirect "/" if logged_in?

    @email = params["email"].to_s.strip
    password = params["password"].to_s
    @demo_account = DEMO_ACCOUNT

    if @email.empty? || password.empty?
      show_error_now("Enter your email and password.")
      halt erb(:"auth/login")
    end

    begin
      auth_session = Mudbase::AuthService.login!(email: @email, password: password)
      store_auth_session!(auth_session)
      flash_notice("Welcome back, #{auth_session.user[:firstName]}!")
      redirect consume_return_to
    rescue Mudbase::AuthError => e
      show_error_now(e.message)
      halt erb(:"auth/login")
    end
  end

  get "/register" do
    redirect "/" if logged_in?
    @first_name = @last_name = @email = ""
    erb :"auth/register"
  end

  post "/register" do
    redirect "/" if logged_in?

    @first_name = params["first_name"].to_s.strip
    @last_name = params["last_name"].to_s.strip
    @email = params["email"].to_s.strip
    password = params["password"].to_s
    agreed_to_terms = params["agreed_to_terms"] == "1"

    errors = validate_registration(@first_name, @last_name, @email, password, agreed_to_terms)
    if errors.any?
      show_error_now(errors.join(" "))
      halt erb(:"auth/register")
    end

    begin
      auth_session = Mudbase::AuthService.register_customer!(
        email: @email,
        password: password,
        first_name: @first_name,
        last_name: @last_name,
        agreed_to_terms: agreed_to_terms,
      )
      store_auth_session!(auth_session)
      flash_notice("Welcome, #{@first_name}!")
      redirect consume_return_to
    rescue Mudbase::AuthError => e
      if e.requires_verification?
        flash_notice(e.message)
        redirect "/login"
      else
        show_error_now(e.message)
        halt erb(:"auth/register")
      end
    end
  end

  post "/logout" do
    Mudbase::AuthService.logout!(access_token) if access_token
    clear_auth_session!
    redirect "/"
  end

  helpers do
    def validate_registration(first_name, last_name, email, password, agreed_to_terms)
      errors = []
      errors << "First name is required." if first_name.empty?
      errors << "Last name is required." if last_name.empty?
      errors << "Enter a valid email address." unless email.match?(EMAIL_PATTERN)
      errors << "Password must be at least 8 characters." if password.length < 8
      errors << "You must agree to the Terms of Service and Privacy Policy." unless agreed_to_terms
      errors
    end
  end
end
