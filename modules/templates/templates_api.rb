require 'templates/handler'

class Proxy::TemplatesApi < Sinatra::Base
  helpers ::Proxy::Helpers

  # When template feature is used, foreman uses this end-point to provide basse url for hosts to fetch templates.
  # It will also modify the rendering of the foreman_url specified in the templates.
  get "/templateServer" do
    begin
      content_type :json
      {"templateServer" => (Proxy::Templates::Plugin.settings.template_url || "")}.to_json
    rescue => e
      log_halt 400, e
    end
  end

  get "/*" do
   log_halt(500, "Failed to retrieve #{params[:splat].first} for #{params[:token]}: ") do
     Proxy::Templates::Handler.get_template(URI::encode(params[:splat].first), params[:token], params[:static])
    end
  end
end
