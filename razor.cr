require "redis"

class Razor

  def initialize(ttl, soa, banner, host, port)
    @ttl = ttl
    @soa = soa
    @banner = banner
    @redis = Redis.new(host, port)
  end

  def ttl
    @ttl
  end

  def soa
    @soa
  end

  def getDataRedis(qtype, name)
    @redis.srandmember("#{name}-#{qtype}")
  end

  def answer(options = {} of String => String|Int32)
    options = {
      "id" => -1,
      "class" => "IN",
      "ttl" => @ttl
    }.merge options
    respond "DATA", options["name"], options["class"], options["type"], options["ttl"], options["id"], options["content"]
  end

  def respond(*args)
    STDOUT.print(args.join("\t") + "\n")
  end

  def finish
    respond "END"
  end

  def banner
    STDIN.read_line
    respond "OK", @banner
  end

  def parseQuery(input)
    query = input.chomp.split("\t")
    if query.size >= 6
      name = query[1]
      qtype = query[3]
    end
    return name, qtype
  end
end

dns = Razor.new(30,
                "example.com. hostmaster.example.com. 2015123006 600 600 604800 600",
                "Razor DNS backend",
                "127.0.0.1",
                6379)

dns.banner

while true

  name, qtype = dns.parseQuery STDIN.read_line

  case qtype
  when "SOA"
    options = {
      "name" => name,
      "type" => qtype,
      "content" => dns.soa
    }
    dns.answer options
  when "ANY"
    %w(A AAAA).each do |type|
      content = dns.getDataRedis(type, name)
      next unless content
      options = {
        "name" => name,
        "type" => type,
        "content" => content
      }
      dns.answer options
    end
  end

  dns.finish
end
