require "./helper"

describe "GeoIP" do
  it "Initialize Razor" do
    RazorTest.new.razor
  end

  it "Create mandatory zone stuff for GeoIP in Redis" do
    razor_test = RazorTest.new
    redis_unixsocket = razor_test.redis_unixsocket
    razor_zone = razor_test.razor_zone
    redis = Redis.new(unixsocket: redis_unixsocket)
    redis.hmset(razor_zone, {
      "SOA":    "#{razor_zone}. hostmaster.#{razor_zone}. 2023012433 600 600 604800 600",
      "TTL":    60,
      "ANSWER": "geoip",
    })
    redis.hmget(razor_zone, "ANSWER").should eq(["geoip"])
  end

  it "Create specific routes (PoP) in Redis" do
    razor_test = RazorTest.new
    redis_unixsocket = razor_test.redis_unixsocket
    razor_zone = razor_test.razor_zone
    redis = Redis.new(unixsocket: redis_unixsocket)
    redis.sadd("#{razor_zone}:A", "10.0.0.1")
    redis.sadd("#{razor_zone}:AAAA", "2a02:4780::1")
    redis.sadd("lt-bnk1.routes.example.org:A", "10.0.1.1")
    redis.sadd("lt-bnk1.routes.example.org:AAAA", "2a02:478:1::1")
    redis.sadd("lt-bnk2.routes.example.org:A", "10.0.1.2")
    redis.sadd("lt-bnk2.routes.example.org:AAAA", "2a02:478:1::2")
    redis.sadd("us-phx1.routes.example.org:A", "10.0.2.1")
    redis.sadd("us-phx1.routes.example.org:AAAA", "2a02:4780:2::1")
    sort(redis.smembers("#{razor_zone}:A")).should eq(["10.0.0.1"])
    sort(redis.smembers("#{razor_zone}:AAAA")).should eq(["2a02:4780::1"])
    redis.srandmember("lt-bnk1.routes.example.org:A").should eq("10.0.1.1")
    redis.srandmember("us-phx1.routes.example.org:AAAA").should eq("2a02:4780:2::1")
  end

  it "Create GeoIP routes in Redis" do
    razor_test = RazorTest.new
    redis_unixsocket = razor_test.redis_unixsocket
    redis = Redis.new(unixsocket: redis_unixsocket)
    redis.set("geoip:eu:lt", "lt-bnk1.routes.example.org")
    redis.set("geoip:eu", "lt-bnk2.routes.example.org")
    redis.set("geoip:na", "us-phx1.routes.example.org")
    redis.get("geoip:na").should eq("us-phx1.routes.example.org")
    redis.get("geoip:eu:lt").should eq("lt-bnk1.routes.example.org")
  end

  it "Check if GeoDNS returns proper pools by source address" do
    razor = RazorTest.new.razor
    qname = "donatas.net.cdn.example.org"
    options = razor.mandatory_dns_options(qname)

    # Lithuania gets IPs from lt-bnk1.routes.example.org pool
    razor.data_from_redis("A", qname, "193.219.39.234", options).should eq(["10.0.1.1"])
    razor.data_from_redis("AAAA", qname, "2a03:1960::", options).should eq(["2a02:478:1::1"])

    # United Kingdom gets IPs from lt-bnk2.routes.examle.org pool
    razor.data_from_redis("A", qname, "31.170.164.0", options).should eq(["10.0.1.2"])
    razor.data_from_redis("AAAA", qname, "2a02:8800::", options).should eq(["2a02:478:1::2"])

    # United States gets IPs from us-phx1.routes.example.org pool
    razor.data_from_redis("A", qname, "32.47.115.0", options).should eq(["10.0.2.1"])
    razor.data_from_redis("AAAA", qname, "2a0d:d900::", options).should eq(["2a02:4780:2::1"])

    # Others gets IPs from cdn.example.org pool
    razor.data_from_redis("A", qname, "102.164.115.0", options).should eq(["10.0.0.1"])
    razor.data_from_redis("AAAA", qname, "2a06:4b80::", options).should eq(["2a02:4780::1"])

    # Others gets IPs from cdn.example.org pool, not found in GeoIP database
    razor.data_from_redis("A", qname, "127.0.0.1", options).should eq(["10.0.0.1"])
    razor.data_from_redis("AAAA", qname, "::1", options).should eq(["2a02:4780::1"])
  end

  it "Check if specific domains are sticked to an arbitrary PoP" do
    qname = "donatas1.net.cdn.example.org"
    razor_test = RazorTest.new
    redis_unixsocket = razor_test.redis_unixsocket
    redis = Redis.new(unixsocket: redis_unixsocket)
    redis.set(qname, "lt-bnk2.routes.example.org")
    razor = RazorTest.new.razor
    options = razor.mandatory_dns_options(qname)
    razor.data_from_redis("A", qname, "32.47.115.0", options).should eq(["10.0.1.2"])
    razor.data_from_redis("AAAA", qname, "2a06:4b80::", options).should eq(["2a02:478:1::2"])
  end
end
