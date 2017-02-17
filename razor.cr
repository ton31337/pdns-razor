require "redis"
require "logger"

class Razor

  def initialize(unixsocket = nil, host = "127.0.0.1", port = 6379, types = %w(NS AAAA A), banner = "Razor DNS backend", debug = false)
    @types = types
    @banner = banner
    @redis = Redis.new(host: host, port: port, unixsocket: unixsocket)
    @debug = debug
    @log = Logger.new(STDERR)
    @log.level = Logger::INFO
  end

  def run!
    banner
    mainLoop
  end

  def mainLoop
    loop do
      name, qtype = parseQuery STDIN.read_line
      ttl = getTTL(name)

      case qtype
      when "SOA"
        options = {
          :name => name,
          :type => qtype,
          :ttl => ttl,
          :content => getSOA(name)
        }
        answer options
      when "ANY"
        @types.each do |type|
          getDataRedis(type, name).each do |response|
            options = {
              :name => name,
              :type => type,
              :ttl => ttl,
              :content => response
            }
            answer options
          end
        end
      end
      finish
    end
  end

  private def getTTL(name)
    @redis.hmget(name, "TTL").first || 60
  end

  private def getSOA(name)
    @redis.hmget(name, "SOA").first
  end

  private def getDataRedis(qtype, name)
    ifdef cname
      name = @redis.get(name)
    end

    case qtype
    when "NS"
      @redis.smembers("#{name}:#{qtype}")
    else
      [@redis.srandmember("#{name}:#{qtype}")]
    end
  end

  private def answer(options = {} of Symbol => String|Int32)
    options = {
      :id => -1,
      :class => "IN"
    }.merge options
    if options[:content]
      @log.info("DATA #{options[:name]} #{options[:type]} #{options[:ttl]} #{options[:content]}") if @debug
      respond "DATA", options[:name], options[:class], options[:type], options[:ttl], options[:id], options[:content]
    end
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

  private def parseQuery(input)
    _, name, _, qtype, _, _ = input.chomp.split("\t")
    return name, qtype
  end
end

Razor.new(unixsocket: "/var/run/redis/6379/redis.sock", debug: true).run!
