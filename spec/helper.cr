require "spec"
require "redis"
require "../src/razor"

def sort(a)
  unless a.is_a? Array(Redis::RedisValue)
    raise "Cannot sort this: #{a.class}"
  end

  convert_to_string_array(a).sort
end

def convert_to_string_array(a)
  a.map { |item| item.to_s }
end

class RazorTest
  @redis_unixsocket : (JSON::Any | Nil)
  @razor_zone : (JSON::Any | Nil)

  def initialize(file = "./test/razor.json")
    @config = file
    @context = "test"
    File.open(file) do |f|
      config = JSON.parse(f)
      if config["contexts"]
        context = config["contexts"][@context]
        @redis_unixsocket = context["redis_unixsocket"]
        @razor_zone = context["zone"]
      end
    end
  end

  def redis_unixsocket
    @redis_unixsocket.to_s
  end

  def razor_zone
    @razor_zone.to_s
  end

  def razor
    Razor.new(config = @config, context = "test")
  end
end
