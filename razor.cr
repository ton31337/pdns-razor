require "redis"

class Razor

  def initialize(unixsocket = nil, host = "127.0.0.1", port = 6379, types = %w(A), ttl = 30, banner = "Razor DNS backend", default_route = "default.route", soa_domain = "000webhost.awex.io")
    @types = types
    @banner = banner
    @ttl = ttl
    @default_route = default_route
    @soa_domain = soa_domain
    @redis = Redis.new(host: host, port: port, unixsocket: unixsocket)
  end

  def run!
    banner
    mainLoop
  end

  def mainLoop
    loop do
      name, qtype = parseQuery STDIN.read_line

      case qtype
      when "SOA"
        options = {
          :name => name,
          :type => qtype,
          :content => "#{name}. hostmaster.#{name}. 2015123006 600 600 604800 600"
        }
        answer options if name.includes?(@soa_domain)
      when "ANY"
        @types.each do |type|
          options = {
            :name => name,
            :type => type,
            :content => getDataRedis(type, name)
          }
          answer options
        end
      end
      finish
    end
  end

  private def getDataRedis(qtype, name)
    ifdef cname
      name = @redis.get(name)
    end
    @redis.srandmember("#{name}:#{qtype}") || @redis.srandmember("#{@default_route}:#{qtype}")
  end

  private def answer(options = {} of Symbol => String|Int32)
    options = {
      :id => -1,
      :class => "IN",
      :ttl => @ttl
    }.merge options
    respond "DATA", options[:name], options[:class], options[:type], options[:ttl], options[:id], options[:content]
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

Razor.new(types: %w(A AAAA), ttl: 60).run!
