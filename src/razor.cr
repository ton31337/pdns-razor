require "redis"
require "logger"
require "big"
require "geoip2"
require "option_parser"
require "json"
require "digest/md5"
require "schedule"
require "ipaddress"

class Razor
  VERSION = {{ read_file("shard.yml").lines[1] }}
  NAME    = "Razor"

  @zone : (String | Nil)
  @geoip_db_checksum : (String | Nil)

  def initialize(config = "/etc/pdns-razor/razor.json", context = "production")
    @config = config
    @context = context
    @banner = "Razor DNS backend"
    @types = %w(SOA NS AAAA A)
    @redis_host = "127.0.0.1"
    @redis_port = 6379
    @redis_unixsocket = "/tmp/redis.sock"
    @debug = false
    @log = Logger.new(STDERR)
    @hash_method = "edns"
    @zone = nil
    @geoip_db_path = "/usr/share/GeoIP/GeoIP2-Country.mmdb"

    parse_arguments

    @geoip = GeoIP2.open(@geoip_db_path)
    @geoip_db_checksum = geoip_db_checksum
    @redis = Redis.new(host: @redis_host,
      port: @redis_port,
      unixsocket: @redis_unixsocket)
  end

  def parse_arguments
    OptionParser.parse do |parser|
      parser.banner = "Usage: ./razor -f <config-path>"
      parser.on("-f CONFIG", "--file=CONFIG", "Configuration file, default: #{@config}") do |file|
        @config = file
      end
      parser.on("-c CONTEXT", "--context=CONTEXT", "Context to use, default: #{@context}") do |context|
        @context = context
      end
      parser.on("-v", "--version", "Show version") do |_|
        puts VERSION
        exit
      end
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
      parser.invalid_option do |flag|
        @log.error("#{flag} is not a valid option")
        @log.error(parser)
        exit(1)
      end
    end

    File.open(@config) do |file|
      config = JSON.parse(file)

      unless config["contexts"]
        @log.error("can't parse JSON #{@config} configuration file")
        exit(1)
      end

      begin
        context = config["contexts"][@context]

        @banner = context["banner"].as_s if context["banner"]?
        @debug = context["debug"].as_bool if context["debug"]?
        @hash_method = context["hash_method"].as_s if context["hash_method"]?
        @redis_host = context["redis_host"].as_s if context["redis_host"]?
        @redis_port = context["redis_port"].as_i if context["redis_port"]?
        @redis_unixsocket = context["redis_unixsocket"].as_s if context["redis_unixsocket"]?
        @zone = context["zone"].as_s if context["zone"]?
        if context["geoip_db_path"]?
          @geoip_db_path = context["geoip_db_path"].as_s
        end
      rescue
        @log.error("no such context found #{@context} or missing configuration in JSON")
        exit(1)
      end

      @log.info("Loading with configuration: #{context}")
    end
  end

  def run!
    banner
    mainLoop
  end

  def mainLoop
    Schedule.every(5.seconds) do
      geoip_db_check
    end

    loop do
      qname, qtype, src, edns = parse_query STDIN.read_line
      qname = qname.downcase
      edns = edns.split("/")[0]
      hash_source = @hash_method == "edns" ? edns : src

      mandatory_options = mandatory_dns_options(qname)

      case qtype
      when "SOA"
        options = {
          :name    => qname,
          :type    => qtype,
          :ttl     => mandatory_options[:ttl],
          :content => mandatory_options[:soa],
        }
        answer(hash_source, options)
      when "ANY"
        # If debug is enabled, query backend for TXT records
        # additionally.
        @types = %w(SOA NS AAAA A TXT) if @debug
        @types.each do |type|
          data_from_redis(type, qname, hash_source, mandatory_options).each do |response|
            options = {
              :name    => qname,
              :type    => type,
              :ttl     => mandatory_options[:ttl],
              :content => response,
            }
            answer(hash_source, options)
          end
        end
      end
      finish
    end
  end

  private def geoip_db_checksum
    digest = Digest::MD5.digest do |ctx|
      ctx.update File.read(@geoip_db_path)
    end
    digest.to_slice.hexstring
  end

  private def geoip_db_check
    # If the checksum changed of the .mmdb file, close, and
    # reopen to handle this internally, without PowerDNS restart.
    new_geoip_db_checksum = geoip_db_checksum
    if @geoip_db_checksum != new_geoip_db_checksum
      @geoip = GeoIP2.open(@geoip_db_path)
      @geoip_db_checksum = new_geoip_db_checksum
    end
  end

  def mandatory_dns_options(name)
    name = @zone || name
    # SOA record MUST be created, otherwise no other
    # content will be returned at all.
    soa, ns, ttl, answer_type = @redis.hmget("#{name}:CONFIG", "SOA", "NS", "TTL", "ANSWER")
    {
      soa:         soa,
      ns:          ns.to_s.delete(" ").split(","),
      ttl:         ttl || 60,
      answer_type: answer_type || "random",
    }
  end

  private def geoip_data(ip)
    return nil, nil unless ip

    # Make sure we can handle errors when querying non-existing IPs in DB.
    # E.g.: 127.0.0.1.
    begin
      rec = @geoip.country(ip)
      continent = rec.continent.code
      country = rec.country.iso_code
      if !continent && !country
        if @debug
          @log.warn("No continent/country found for #{ip}")
        end
        return nil, nil
      end
      return continent, country
    rescue
      @log.warn("GeoIP information not found for #{ip}")
      return nil, nil
    end

    return continent, country
  end

  private def to_sorted_array_of_string(array)
    array.map do |item|
      item.to_s
    end.sort
  end

  private def ipv4_int(ip)
    ip_int = 0.to_big_i
    ip.split(".").each_with_index do |oct, i|
      ip_int |= oct.to_big_i << (32 - 8 * (i + 1))
    end
    ip_int
  end

  private def ipv6_decompress(ip)
    ip_arr = [] of String
    splitted = ip.split("")
    compressed = 8 - ip.split(":").size
    splitted.size.times do |i|
      ip_arr << splitted[i]
      if splitted[i] == ":" && splitted[i + 1]? == ":"
        compressed.times do |_|
          ip_arr << "0" << ":"
        end
        ip_arr << "0"
      end
    end
    ip_arr.join
  end

  private def ipv6_int(ip)
    ip_int = 0.to_big_i
    ipv6_decompress(ip).split(":").each_with_index do |word, i|
      ip_int |= word.rjust(4, '0').to_big_i(16) << (128 - 16 * (i + 1))
    end
    ip_int
  end

  def ipv4_get(range, skip_list, seed = UInt8::MAX)
    ip = IPAddress.new range.to_s
    random_ip = random_last_octet_get(ip, seed)
    skip_list.each do |skip_ip|
      return ipv4_get(range, skip_list, seed) if random_ip == skip_ip
    end
    random_ip
  end

  # Generate only the last 8-bits of random data for IPv4
  private def random_last_octet_get(ip, seed)
    ip[3] = rand(seed)
    ip.address
  end

  # Get the random IPv6 address from the given range,
  # and exclude the ones that are listed as skip-list (= blackholed).
  # This mechanism works only with /48 ranges and checks
  # are based on /64 ranges.
  def ipv6_get(range, skip_list, seed = UInt16::MAX)
    ip = IPAddress.new range.to_s
    random_ip = random_eui64_get(ip, seed)
    skip_list.each do |s|
      skip_ip = IPAddress.new s.to_s
      return ipv6_get(range, skip_list, seed) if eui64_cmp(random_ip, skip_ip)
    end
    random_ip.address
  end

  # Generate only the last 64-bits of random data
  private def random_eui64_get(ip, seed)
    ip[3] = rand(seed)
    ip[4] = rand(seed)
    ip[5] = rand(seed)
    ip[6] = rand(seed)
    ip[7] = rand(seed)
    ip
  end

  # Compare the first 64-bits (EUI-64), and just
  # ignore the rest of the identifier bits because
  # most of the DDoS attack-related blackholings
  # occur using /64, not /128, etc.
  private def eui64_cmp(ip1, ip2)
    if ip1[0] == ip2[0] &&
       ip1[1] == ip2[1] &&
       ip1[2] == ip2[2] &&
       ip1[3] == ip2[3]
      return true
    end
    false
  end

  private def ip_hashed(ip, count)
    if ip.includes?(":")
      (ipv6_int(ip) >> (128 - 48)) % count
    else
      (ipv4_int(ip) & 0xffffff00) % count
    end
  end

  private def servers_count(name)
    @redis.smembers(name).size
  end

  private def dns_groups(name)
    @redis.smembers("#{name}:GROUPS") || [] of String
  end

  private def skip_list(qtype)
    @redis.smembers("#{@zone}:#{qtype}:SKIPLIST")
  end

  # Get random IPv4/IPv6 range from Redis, and then pick the
  # random address from the given range (randomized from Redis).
  private def random_ip_get(qname, qtype)
    ip = @redis.srandmember("#{qname}:#{qtype}")
    if ip && ip.includes?("/")
      case qtype
      when "AAAA"
        return ipv6_get(ip, skip_list(qtype))
      when "A"
        return ipv4_get(ip, skip_list(qtype))
      end
    end

    ip
  end

  private def ch_content(name, src)
    count = servers_count(name)
    return if count == 0
    hash = ip_hashed(src, count)
    to_sorted_array_of_string(@redis.smembers(name))[hash]
  end

  private def gch_content(qtype, groups, src)
    hash = ip_hashed(src, groups.size)
    @redis.srandmember("#{groups[hash]}:#{qtype}")
  end

  private def geoip_content(qname, qtype, src)
    # Process GeoIP here, and return the pool by the
    # country/continent.
    # In Redis, the keys MUST keep the following encoding:
    #   geoip:eu
    #   geoip:eu:lt
    #   geoip:eu:uk
    #   geoip:na
    #   geoip:na:us
    #   ...
    #
    # Redis KEY returns the VALUE of something like:
    #   GET geoip:eu:lt
    #   uk1.routes.example.net
    # Subsequent requests will use the scheme as below:
    #   SRANDMEMBER uk1.routes.example.net:A
    #   SRANDMEMBER uk1.routes.example.net:AAAA
    #
    # The first request checks if we can return A/AAAA from
    # the pool which is under the country. If not found, then
    # check by continent.
    # Moreover, even if the continent does not exist, then
    # return random IP from the default zone:A, zone:AAAA.
    route : (Redis::RedisValue | String | Nil) = nil
    continent : (String | Nil) = nil
    country : (String | Nil) = nil

    # If we want to stick specific qname to an arbitrary PoP
    # instead of relying on GeoIP data, just create a key in Redis
    # like:
    #   SET donatas.net.<default_zone> uk1.routes.example.net
    begin
      r_name = @redis.get(qname)
      if r_name
        name = r_name
      else
        name = @zone || qname
        continent, country = geoip_data(src)
      end

      # Fetch continent:country and continent in batched mode (MGET),
      # to save one additional request to Redis.
      if continent && country
        route_country, route_continent = @redis.mget("geoip:#{continent.downcase}:#{country.downcase}",
          "geoip:#{continent.downcase}")
        route = route_country || route_continent
      elsif continent
        route = @redis.get("geoip:#{continent.downcase}")
      end

      if route
        return random_ip_get(route, qtype), continent, country
      end
    rescue Redis::Error
      @log.error("Something went wrong, key: '#{qname}:#{qtype}', src: #{src}")
    end

    # If GeoIP is skipped, return more specific PoP or the default @zone
    return random_ip_get(name, qtype), nil, nil
  end

  def data_from_redis(qtype, name, src, options)
    case qtype
    when "SOA"
      [options[:soa]]
    when "NS"
      options[:ns]
    when "TXT"
      ip, continent, country = geoip_content(name, src.includes?(":") ? "AAAA" : "A", src)
      if continent && country
        ["#{NAME}/#{src} (#{continent}:#{country})/#{ip}"]
      else
        ["#{NAME}/#{src}/#{ip}"]
      end
    else
      case options[:answer_type]
      when "random"
        [random_ip_get(name, qtype)]
      when "consistent_hash"
        [ch_content("#{name}:#{qtype}", src)]
      when "group_consistent_hash"
        [gch_content(qtype, to_sorted_array_of_string(dns_groups(name)), src)]
      when "geoip"
        ip, _, _ = geoip_content(name, qtype, src)
        [ip]
      else
        [] of String
      end
    end
  end

  private def answer(src, options = {} of Symbol => String | Int32)
    options = {
      :scopebits => src.includes?(":") ? 48 : 24,
      :auth      => 1,
      :id        => -1,
      :class     => "IN",
    }.merge options
    respond "DATA",
      options[:scopebits],
      options[:auth],
      options[:name],
      options[:class],
      options[:type],
      options[:ttl],
      options[:id],
      options[:content] if options[:content]
  end

  private def respond(*args)
    STDOUT.print(args.join("\t") + "\n")
  end

  private def finish
    respond "END"
  end

  private def banner
    STDIN.read_line
    respond "OK", @banner
  end

  private def parse_query(input)
    _, name, _, qtype, _, src, _, edns = input.chomp.split("\t")
    return name, qtype, src, edns
  end
end
