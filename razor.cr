require "redis"
require "logger"
require "big"
require "geoip2"
require "option_parser"
require "json"

class Razor
  @zone : (String | Nil)

  def initialize
    @config = "/etc/pdns/razor.json"
    @context = "production"
    @banner = "Razor DNS backend"
    @types = %w(SOA NS AAAA A)
    @redis_host = "127.0.0.1"
    @redis_port = 6379
    @redis_unixsocket = "/tmp/redis.sock"
    @redis = Redis.new(host: @redis_host,
      port: @redis_port,
      unixsocket: @redis_unixsocket)
    @debug = false
    @log = Logger.new(STDERR)
    @log.level = Logger::INFO
    @hash_method = "edns"
    @zone = nil
    @geoip_db_path = "/usr/share/GeoIP/GeoIP2-Country.mmdb"
    @geoip = GeoIP2.open(@geoip_db_path)

    parse_arguments
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
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
      parser.invalid_option do |flag|
        STDERR.puts "ERROR: #{flag} is not a valid option."
        STDERR.puts parser
        exit(1)
      end
    end

    File.open(@config) do |file|
      config = JSON.parse(file)

      unless config["contexts"]
        STDERR.puts "ERROR: Can't parse JSON #{@config} configuration file."
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
          @geoip = GeoIP2.open(@geoip_db_path)
        end
      rescue
        STDERR.puts "ERROR: No such context found #{@context} or missing configuration in JSON."
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
    loop do
      qname, qtype, src, edns = parse_query STDIN.read_line
      name = @zone || qname.downcase
      ttl = ttl(name)
      edns = edns.split("/")[0]
      hash_source = @hash_method == "edns" ? edns : src

      case qtype
      when "SOA"
        options = {
          :name    => name,
          :type    => qtype,
          :ttl     => ttl,
          :content => soa(name),
        }
        answer(hash_source, options)
      when "ANY"
        @types.each do |type|
          data_from_redis(type, name, hash_source).each do |response|
            options = {
              :name    => name,
              :type    => type,
              :ttl     => ttl,
              :content => response,
            }
            answer(hash_source, options)
          end
        end
      end
      finish
    end
  end

  private def ip_country(ip)
    rec = @geoip.country(ip)
    rec.country.iso_code.downcase
  end

  private def ip_continent(ip)
    rec = @geoip.country(ip)
    rec.continent.code.downcase
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

  private def ip_hashed(ip, count)
    if ip.includes?(":")
      (ipv6_int(ip) >> (128 - 48)) % count
    else
      (ipv4_int(ip) & 0xffffff00) % count
    end
  end

  private def ttl(name)
    @redis.hmget(name, "TTL").first || 60
  end

  private def soa(name)
    # SOA record MUST be created, otherwise no other
    # content will be returned at all.
    @redis.hmget(name, "SOA").first
  end

  private def answer_type(name)
    @redis.hmget(name, "ANSWER").first || "random"
  end

  private def servers_count(name)
    @redis.smembers(name).size
  end

  private def dns_groups(name)
    @redis.smembers("#{name}:GROUPS") || [] of String
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

  private def geoip_content(name, src)
    # Proess GeoIP here, and return the pool by the
    # country/continent.
    count = servers_count(name)
    return if count == 0
    hash = ip_hashed(src, count)
    to_sorted_array_of_string(@redis.smembers(name))[hash]
  end

  private def data_from_redis(qtype, name, src)
    case qtype
    when "SOA"
      [soa(name)]
    when "NS"
      @redis.smembers("#{name}:#{qtype}")
    else
      case answer_type(name)
      when "random"
        [@redis.srandmember("#{name}:#{qtype}")]
      when "consistent_hash"
        [ch_content("#{name}:#{qtype}", src)]
      when "group_consistent_hash"
        [gch_content(qtype, to_sorted_array_of_string(dns_groups(name)), src)]
      when "geoip"
        [geoip_content("#{name}:#{qtype}", src)]
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
    @log.info(args.join("\t") + "\n") if @debug
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
    @log.info(input.chomp) if @debug
    return name, qtype, src, edns
  end
end

Razor.new.run!
