module LoginCommands

  URL_BASE = 'https://steamcommunity.com'

  def login(steam_id: nil)
    response = @session.post("#{URL_BASE}/login/getrsakey/", { 'username' => @username }).content
    data = pass_stamp(response, @password)
    encrypted_password = data["password"]
    timestamp = data["timestamp"]

    login_data = {
      'password' => encrypted_password,
      'username' => @username,
      'twofactorcode' => '', # update
      'emailauth' => '',
      'loginfriendlyname' => '',
      'captchagid' => '-1',
      'captcha_text' => '',
      'emailsteamid' => '',
      'rsatimestamp' => timestamp,
      'remember_login' => @remember
    }

    login = @session.post("#{URL_BASE}/login/dologin", login_data).content
    
    first_request = JSON.parse(login)

    raise "Incorrect username or password" if first_request["message"] == "The account name or password that you have entered is incorrect."

    until first_request["success"] == true
      sleep(0.3)
      gid = '-1'
      cap = ''
      if first_request['captcha_needed'] == true
        gid = first_request['captcha_needed']
        File.delete("./#{username}_captcha.png") if File.exist?("./#{username}_captcha.png")
        @session.get("#{URL_BASE}/login/rendercaptcha?gid=#{gid}").save "./#{@username}_captcha.png"
        puts "you need to write a captcha to continue"
        puts "there is an image named #{@username}_captcha in the script directory"
        puts "open it and write the captha here"
        cap = gets.chomp
      end

      emailauth = ''
      facode = ''
      emailsteamid = ''
      if first_request['requires_twofactor'] == true
        if @secret.nil?
          puts "write 2FA code"
          facode = gets.chomp
        else
          facode = fa(@secret, @time_difference)
        end
      elsif first_request['emailauth_needed'] == true
        emailsteamid = first_request['emailsteamid']
        puts "Guard code was sent to your email"
        puts "write the code"
        emailauth = gets.chomp
      end

      send = {
        'password' => encrypted_password,
        'username' => @username,
        'twofactorcode' => facode, # update
        'emailauth' => emailauth,
        'loginfriendlyname' => '',
        'captchagid' => gid,
        'captcha_text' => cap,
        'emailsteamid' => emailsteamid,
        'rsatimestamp' => timestamp,
        'remember_login' => @remember
      }
      output "attempting to login"
      login = @session.post("#{URL_BASE}/login/dologin", send).content
      first_request = JSON.parse(login)
    end

    response = first_request

    if response['transfer_parameters'] && @steam_id != response["transfer_parameters"]["steamid"]
      output "The steamId you provided does not belong to the account you entered"
      output "SteamId will be overwritten"
      @steam_id = response["transfer_parameters"]["steamid"] if response['transfer_parameters']
    elsif steam_id.present?
      @steam_id = steam_id
    end

    if response["transfer_urls"]
      response["transfer_urls"].each { |url|
        @session.post(url, response["transfer_parameters"])
      }
    end

    steampowered_sessionid = ''
    @session.cookies.each { |c|
      if c.name == "sessionid"
        steampowered_sessionid = c.value
      end
    }

    cookie = Mechanize::Cookie.new :domain => 'steamcommunity.com', :name => 'sessionid', :value => steampowered_sessionid, :path => '/'
    @session.cookie_jar << cookie
    @logged_in = true

    try_to_load_api_key unless @api_key

    unless @api_key.nil?
      data = get_player_summaries(@steam_id)
      data.each { |element|
        if element["steamid"].to_s == @steam_id.to_s
          @persona = element["personaname"]
        end
      }
    end
    output "Logged in as #{@persona}"
    output "Your SteamId is #{@steam_id}"
    output "Steam API_KEY : #{@api_key}" unless @api_key.nil?
  end

  def pass_stamp(give, password)
    data = JSON::parse(give)
    mod = data["publickey_mod"].hex
    exp = data["publickey_exp"].hex

    # mod = data["publickey_mod"]
    # exp = data["publickey_exp"]
    timestamp = data["timestamp"]

    key = OpenSSL::PKey::RSA.new
    if RUBY_VERSION.to_f <= 2.3
      key.e = OpenSSL::BN.new(exp)
      key.n = OpenSSL::BN.new(mod)
    elsif RUBY_VERSION.to_f >= 2.4
      # key.set_key(n, e, d)
      # key.set_key(OpenSSL::BN.new(mod), OpenSSL::BN.new(exp), nil)
      key = create_rsa_key mod, exp
    end
    ep = Base64.encode64(key.public_encrypt(password.force_encoding("utf-8"))).gsub("\n", '')
    return { 'password' => ep, 'timestamp' => timestamp }
  end

  def create_rsa_key(n, e)
    data_sequence = OpenSSL::ASN1::Sequence([
                                              # OpenSSL::ASN1::Integer(base64_to_long(n)),
                                              # OpenSSL::ASN1::Integer(base64_to_long(e))
                                            OpenSSL::ASN1::Integer(n),
                                            OpenSSL::ASN1::Integer(e)
                                            ])
    asn1 = OpenSSL::ASN1::Sequence(data_sequence)
    OpenSSL::PKey::RSA.new(asn1.to_der)
  end

  def base64_to_long(data)
    decoded_with_padding = Base64.urlsafe_decode64(data) + Base64.decode64("==")
    decoded_with_padding.to_s.unpack("C*").map do |byte|
      byte_to_hex(byte)
    end.join.to_i(16)
  end

  def byte_to_hex(int)
    int < 16 ? "0" + int.to_s(16) : int.to_s(16)
  end
  #
  # -----
  ########################################################################################

end
