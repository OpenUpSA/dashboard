require 'dashing'
require 'securerandom'

$:.unshift(File.dirname(__FILE__) + '/lib')
require 'websites'

configure do
  # default auth token to a random string
  set :auth_token, ENV['DASHING_AUTH_TOKEN'] || SecureRandom.hex
  set :basic_auth_user, ENV['BASIC_AUTH_USER']
  set :basic_auth_pass, ENV['BASIC_AUTH_PASS']

  helpers do
    def protected!
      unless authorized?
        response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
        throw(:halt, [401, "Not authorized\n"])
      end
    end

    def authorized?
      return true if not settings.basic_auth_user or settings.basic_auth_user.empty?

      @auth ||=  Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [settings.basic_auth_user, settings.basic_auth_pass]
    end

    def websites
      get_websites
    end
  end
end

map Sinatra::Application.assets_prefix do
  run Sinatra::Application.sprockets
end

run Sinatra::Application
