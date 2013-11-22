require 'base64'
require 'gssapi'
require 'proxy/kerberos'
require 'xmlrpc/client'

module Proxy::Realm
  class FreeIPA < Client
    include Proxy::Kerberos

    def initialize
      keytab = SETTINGS.realm_keytab
      principal = SETTINGS.realm_principal
      logger.debug "freeipa: realm keytab is #{keytab} using principal #{principal}"

      # Read FreeIPA Configuration
      File.readlines("/etc/ipa/default.conf").each do |line|
        if line =~ /xmlrpc_uri/
          @ipa_server = URI.parse line.split("=")[1].strip
        elsif line =~ /realm/
          @realm_name = line.split("=")[1].strip
        end
      end
      logger.debug "freeipa: server is #{@ipa_server} for realm #{@realm_name}"
      raise Proxy::Realm::Error.new "Unable to read FreeFreeIPA client configuration." unless @ipa_server
      raise Proxy::Realm::Error.new "Keytab not configured via freeipa_keytab for GSSAPI support" unless keytab
      raise Proxy::Realm::Error.new "Unable to read freeipa_keytab file at #{keytab}" unless File.exist?(keytab)

      # Get krb5 token
      init_krb5_ccache keytab, principal
      gssapi = GSSAPI::Simple.new(@ipa_server.host, "HTTP")
      token = gssapi.init_context

      # FreeIPA API returns some nils, Ruby XML-RPC doesn't like this
      XMLRPC::Config.module_eval { const_set(:ENABLE_NIL_PARSER, true) }

      @ipa = XMLRPC::Client.new2(@ipa_server.to_s)
      @ipa.http_header_extra={ 'Authorization'=>"Negotiate #{Base64.strict_encode64(token)}",
                               'Referer' => @ipa_server.to_s,
                               'Content-Type' => 'text/xml; charset=utf-8'
                             }
    end

    def format record
      remove_certificate(record) # Remove all "usercertificate" keys that FreeIPA returns - it breaks ruby .to_json 
      JSON.pretty_generate(record)
    end

    def remove_certificate record 
      if record.is_a? Hash 
        record.delete "usercertificate"
      else 
        record.each_with_index do |bad_record, idx|
          record[idx] = remove_certificate(bad_record)
        end
      end
    end

    def show realm_name, fqdn
      raise Proxy::Realm::Error.new "Unknown realm #{realm_name}" unless realm_name.eql? @realm_name
      format(@ipa.call("host_show", [fqdn], {"raw" => 0})["result"])
    end

    def create realm_name, params
      raise Proxy::Realm::Error.new "Unknown realm #{realm_name}" unless realm_name.eql? @realm_name

      options = { :force   => 1,
                  :random  => 1,
                  :setattr => [] 
                }

      # Map Foreman Parameters to LDAP Attributes
      attr_map = { "hostgroup" => "userclass" }
      attr_map.each do |param, attr|
        options[:setattr] << "#{attr}=#{params[param]}" if params.has_key? param
      end

      create_result = @ipa.call("host_add", [params[:fqdn]], options)
      format({:result => 0, :hostname => create_result["value"], :otp_password => create_result["result"]["randompassword"]})
    end

    def delete realm_name, fqdn
      raise Proxy::Realm::Error.new "Unknown realm #{realm_name}" unless realm_name.eql? @realm_name
      @ipa.call("host_del", [fqdn], {"updatedns" => SETTINGS.freeipa_remove_dns}).to_s
    end
  end
end
