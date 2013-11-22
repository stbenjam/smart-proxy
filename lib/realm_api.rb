class SmartProxy < Sinatra::Base
  def realm_setup
    raise "Smart Proxy is not configured to support Realm" unless SETTINGS.realm

    case SETTINGS.realm_provider
      when "freeipa"
        require 'proxy/realm/freeipa'
        @realm = Proxy::Realm::FreeIPA.new
      else
        log_halt 400, "Unrecognized or missing Realm provider: #{SETTINGS.realm_provider.nil? ? "MISSING" : SETTINGS.realm_provider}"
    end
    rescue => e
      log_halt 400, e
  end
 
  before do
    realm_setup if request.path_info =~ /realm/
  end

  get "/realm/:name/:fqdn" do
    begin
      content_type :json
      @realm.show params[:name], params[:fqdn]
    rescue Exception => e
      log_halt 404, e
    end
  end

  post "/realm/:name" do 
    begin
      content_type :json
      @realm.create params[:name], params
    rescue Exception => e
      log_halt 400, e
    end
  end

  delete "/realm/:name/:fqdn" do
    begin
      @realm.delete params[:name], params[:fqdn]
    rescue Exception => e
      log_halt 400, e
    end
  end
end
