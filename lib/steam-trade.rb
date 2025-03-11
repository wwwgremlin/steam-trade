require 'mechanize'
require 'json'
require 'openssl'
require 'base64'
require 'open-uri'
require 'thread'

require_relative './LoginExecutor.rb'
require_relative './Misc.rb'
require_relative './Trade.rb'
require_relative './Confirmation.rb'
require_relative './Trade.rb'
require_relative './Inventory.rb'
require_relative './Badge.rb'
require_relative './Guard.rb'
require_relative './Playerinfo.rb'
require_relative './IEconService.rb'
require_relative './Social.rb'
require_relative './EventCards.rb'

class SteamHandler
  include MiscCommands
  include LoginCommands
  include TradeCommands
  include ConfirmationCommands
  include GuardCommands
  include InventoryCommands
  include BadgeCommands
  include GuardCommands
  include PlayerCommands
  include TradeAPI
  include SocialCommands
  include EventCommands

  attr_accessor :secret, :identity_secret, :logged_in


  # secret here is shared_secret
  def initialize(username: nil, password: nil, secret: nil, identity_secret: nil, steam_id: nil,
                 api_key: nil, time_difference: 0, remember_me: false)
    @username = username
    @password = password
    @secret = secret
    @time_difference = time_difference
    @remember = remember_me
    @steam_id = steam_id
    @identity_secret = identity_secret # can and should be initialized using mobile_info
    @api_key = api_key # can be initialized through set_api_key or will be initialized once you login if possilbe

    # Will be set to true once logged in
    @logged_in = false #

    # The session which will hold your cookies to communicate with steam
    @session = Mechanize.new { |a|
      a.user_agent_alias = 'Windows Mozilla'
      a.follow_meta_refresh = true
      a.history_added = Proc.new { sleep 1 }
      #   a.agent.http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    }

    @persona = nil # will be initialized once you login
    @android_id = nil

    @inventory_cache = false
    @lib_dir = Util.gem_libdir
    @messages = true

    @chat_session = nil ## will be initialized if needed
    @oauth_token = nil # required to send messages
    @umqid = nil # required to send messages
    @message_id = nil # requires to send messages

    output "Handler started for #{@username}"

    login(steam_id: @steam_id)

    # TODO try to load cookies if password is not set
    # load_cookies(username)

    try_to_load_api_key unless @api_key
  end

  def mobile_info(identity_secret, steam_id = nil)
    @identity_secret = identity_secret
    @steam_id = steam_id if @steam_id.nil? && !steam_id.nil?
  end

  def set_inventory_cache(timer = 120)
    if timer.is_a?(Numeric)
      @inventory_validity = timer.to_i
      output "Inventory validity set to #{timer}"
    end

    if @inventory_cache
      @inventory_cache = false
      output "Inventory cache disabled"
    else
      @inventory_cache = true
      output "Inventory cache enabled"
    end
  end

  def set_api_key(api_key)
    @api_key = api_key
  end

  def try_to_load_api_key
    begin
      text = Nokogiri::HTML(@session.get("https://steamcommunity.com/dev/apikey").content).css('#bodyContents_ex').css('p').first.text.sub('Key: ', '')
      @api_key = text unless text.include?('Registering for a Steam Web API Key will enable you to access many Steam features from your own website')
    rescue
      output "Could not retrieve api_key"
    end
  end

  def toggle_messages
    @messages = !@messages
    output "Messages are now #{@messages ? 'enabled' : 'disabled'}"
  end

  def get_auth_cookies
    data = {}
    # data['sessionid'] = @session.cookie_jar.jar["steamcommunity.com"]["/"]["sessionid"].value

    begin
      data['steamLogin'] = @session.cookie_jar.jar["store.steampowered.com"]["/"]["steamLogin"].value
      if data['steamLogin'].nil?
        data['steamLogin'] = @session.cookie_jar.jar["steamcommunity.com"]["/"]["steamLogin"].value
      end
    rescue => e
      output "Error happened during get_auth_cookies.steamLogin: #{e}"
    end

    data['steamLoginSecure'] = @session.cookie_jar.jar["store.steampowered.com"]["/"]["steamLoginSecure"].value
    if data['steamLoginSecure'].nil?
      data['steamLoginSecure'] = @session.cookie_jar.jar["steamcommunity.com"]["/"]["steamLoginSecure"].value
    end

    if @steam_id != nil
      data["steamMachineAuth#{@steam_id}"] = @session.cookie_jar.jar["store.steampowered.com"]["/"]["steamMachineAuth#{@steam_id}"].value
      if data["steamMachineAuth#{@steam_id}"].nil?
        data["steamMachineAuth#{@steam_id}"] = @session.cookie_jar.jar["steamcommunity.com"]["/"]["steamMachineAuth#{@steam_id}"].value
      end
    else
      @session.cookies.each { |c|
        if c.downcase.include?('steammachine')
          data[c] = c.value
        end
      }
    end

    data['store_sessionid'] = store_cookie
    data['community_sessionid'] = session_id_cookie
    begin
      data['steamRememberLogin'] = @session.cookie_jar.jar["store.steampowered.com"]["/"]['steamRememberLogin'].value
    rescue
      output "Error happened during get_auth_cookies.steamRememberLogin: #{e}"
    end

    data

  end

  def load_android_id(str)
    @android_id = str
  end

  private

  def load_cookies(data, session = @session)
    container = []
    data.each { |name, value|
      if name.include?("steamMachineAuth")
        container << (Mechanize::Cookie.new :domain => 'store.steampowered.com', :name => name, :value => value, :path => '/')
        container << (Mechanize::Cookie.new :domain => 'steamcommunity.com', :name => name, :value => value, :path => '/')
        container << (Mechanize::Cookie.new :domain => 'help.steampowered.com', :name => name, :value => value, :path => '/')
        @steam_id = name.sub('steamMachineAuth', '')
      elsif name == 'steamLogin'
        container << (Mechanize::Cookie.new :domain => 'store.steampowered.com', :name => name, :value => value, :path => '/')
        container << (Mechanize::Cookie.new :domain => 'steamcommunity.com', :name => name, :value => value, :path => '/')
        container << (Mechanize::Cookie.new :domain => 'help.steampowered.com', :name => name, :value => value, :path => '/')
      elsif name == 'steamLoginSecure'
        container << (Mechanize::Cookie.new :domain => 'store.steampowered.com', :name => name, :value => value, :path => '/')
        container << (Mechanize::Cookie.new :domain => 'steamcommunity.com', :name => name, :value => value, :path => '/')
        container << (Mechanize::Cookie.new :domain => 'help.steampowered.com', :name => name, :value => value, :path => '/')
      elsif name == 'store_sessionid'
        container << (Mechanize::Cookie.new :domain => 'store.steampowered.com', :name => 'sessionid', :value => value, :path => '/')
      elsif name == 'community_sessionid'
        container << (Mechanize::Cookie.new :domain => 'steamcommunity.com', :name => 'sessionid', :value => value, :path => '/')
      elsif name == 'steamRememberLogin'
        container << (Mechanize::Cookie.new :domain => 'store.steampowered.com', :name => name, :value => value, :path => '/')
        container << (Mechanize::Cookie.new :domain => 'steamcommunity.com', :name => name, :value => value, :path => '/')
        container << (Mechanize::Cookie.new :domain => 'help.steampowered.com', :name => name, :value => value, :path => '/')
      end
    }

    container.each { |cookie|
      session.cookie_jar << cookie
    }

    user = Nokogiri::HTML(session.get('https://steamcommunity.com/').content).css('#account_pulldown').text
    raise "Could not login using cookies" if user == ''
    if session == @session
      @logged_in = true
      @username = user
      output "Logged in as #{user}"
    end
  end
end
