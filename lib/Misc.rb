module MiscCommands
  def set_steamid(steam_id)
    raise "Editing SteamID while logged in will cause malfunctions" if @logged_in
    @steam_id, token = verify_profileid_or_trade_link_or_steamid(steam_id)
    output "SteamID set to #{@steam_id}"
  end

  def copy_session
    @session
  end

  def use_session
    @session
  end

  def use_chat_session
    @chat_session
  end

  def partner_id_to_steam_id(account_id)
    unknown_constant = 17825793 # or 0x1100001 idk wtf is this but ....
    first_bytes = [account_id.to_i].pack('i>')
    last_bytes = [unknown_constant].pack('i>')
    collect = last_bytes + first_bytes
    collect.unpack('Q>')[0].to_s
  end

  def output(message)
    return if message.strip.empty?
    time = Time.new
    add = time.strftime("%d-%m-%Y %H:%M:%S")
    puts "#{add} :: #{@username.to_s} :: #{message}"
  end

  def verify_profileid_or_trade_link_or_steamid(steam_id)
    if steam_id.to_i == 0 && steam_id.include?("?partner=") ##supplied trade link
      partner_raw = steam_id.split('partner=', 2)[1].split('&', 2)[0]
      token = steam_id.split('token=', 2)[1]
      steam_id = partner_id_to_steam_id(partner_raw)
      [steam_id, token]
    elsif steam_id.to_i == 0
      parser = Nokogiri::XML(@session.get("https://steamcommunity.com/id/#{steam_id}?xml=1").content)
      if parser.xpath('//error').text == ('The specified profile could not be found.')
        raise "No profile with #{steam_id} as ProfileId"
      end

      steam_id = parser.xpath('//steamID64').text
      return steam_id
    elsif steam_id.to_s.length == 17
      return steam_id
    else
      raise "Invalid SteamId : #{steam_id}, length of received :: #{steam_id.to_s.length}, normal is 17" if steam_id.to_s.length != 17
    end
  end

  def session_id_cookie
    begin
      value = @session.cookie_jar.jar["steamcommunity.com"]["/"]["sessionid"].value
    rescue
      @session.get('http://steamcommunity.com')
      value = @session.cookie_jar.jar["steamcommunity.com"]["/"]["sessionid"].value
    end

    value
  end

  def store_cookie
    begin
      value = @session.cookie_jar.jar["store.steampowered.com"]["/"]["sessionid"].value
    rescue
      @session.get('http://store.steampowered.com')
      value = @session.cookie_jar.jar["store.steampowered.com"]["/"]["sessionid"].value
    end

    value
  end

  def api_call(request_methode, interface, api_methode, version, params = nil)
    url = ["https://api.steampowered.com", "#{interface}", "#{api_methode}", "#{version}"].join('/')
    if request_methode.downcase == "get"
      response = @session.get(url, params)
    elsif request_methode.downcase == "post"
      response = @session.get(url, params)
    else
      raise "Invalid request method: #{request_methode}"
    end
    if response.content.include?("Access is denied")
      raise "Invalid API_key"
    end

    response.content
  end

  def self.included(base)
    # base.extend(Misc_ClassMethods)
  end

  # module Misc_ClassMethods
  #   def partner_id_to_steam_id(account_id)
  #     unknown_constant = 17825793 # or 0x1100001 idk wtf is this but ....
  #     first_bytes = [account_id.to_i].pack('i>')
  #     last_bytes = [unknown_constant].pack('i>')
  #     collect = last_bytes + first_bytes
  #     return collect.unpack('Q>')[0].to_s
  #   end
  #
  #   private
  #
  #   def output(message)
  #     time = Time.new
  #     add = time.strftime("%d-%m-%Y %H:%M:%S")
  #     puts "#{add} :: #{message}"
  #   end
  #
  #   def verify_profileid_or_trade_link_or_steamid(steam_id)
  #     if steam_id.to_i == 0 && steam_id.include?("?partner=") ##supplied trade link
  #       partner_raw = steam_id.split('partner=', 2)[1].split('&', 2)[0]
  #       token = steam_id.split('token=', 2)[1]
  #       steam_id = partner_id_to_steam_id(partner_raw)
  #       return [steam_id, token]
  #     elsif steam_id.to_i == 0
  #       session = Mechanize.new
  #       parser = Nokogiri::XML(session.get("https://steamcommunity.com/id/#{steam_id}?xml=1").content)
  #       if parser.xpath('//error').text == ('The specified profile could not be found.')
  #         raise "No profile with #{steam_id} as ProfileId"
  #       end
  #       steam_id = parser.xpath('//steamID64').text
  #       return steam_id
  #     elsif steam_id.to_s.length == 17
  #       return steam_id
  #     else
  #       raise "Invalid SteamId : #{steam_id}, length of received :: #{steam_id.to_s.length}, normal is 17" if steam_id.to_s.length != 17
  #     end
  #   end
  # end
end

module Util
  def self.gem_libdir
    require_relative 'meta/version.rb'
    t = %W[#{File.dirname(File.expand_path($0))}/#{Meta::GEM_NAME}.rb
                  #{File.expand_path(File.dirname(__FILE__))}/#{Meta::GEM_NAME}.rb
                  #{Gem.dir}/gems/#{Meta::GEM_NAME}-#{Meta::VERSION}/lib/#{Meta::GEM_NAME}.rb]
    t.each { |i|
      return i.gsub("#{Meta::GEM_NAME}.rb", '') if File.readable?(i)
    }
    raise "All paths are invalid: #{t}, while getting gemlib directory"
  end
end
