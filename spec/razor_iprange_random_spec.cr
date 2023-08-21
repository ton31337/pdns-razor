require "./helper"

describe "IP range random generation from the list" do
  it "Check if random IPv6 are generated excluding from the skip-list" do
    ips = [] of String
    ranges = ["2a02:4780:1::/48", "2a02:4780:2::/48"]
    skip_list = ["2a02:4780:1::/64", "2a02:4780:2::/64"]
    razor = RazorTest.new.razor
    ranges.each do |range|
      ips << razor.ipv6_get(range, skip_list, 2)[..18]
    end
    ips.sort.should eq([
      "2a02:4780:0001:0001",
      "2a02:4780:0002:0001",
    ])
  end

  it "Check if random IPv4 are generated excluding from the skip-list" do
    ips = [] of String
    ranges = ["192.168.0.0/24", "192.168.1.0/24"]
    skip_list = ["192.168.0.1", "192.168.1.1"]
    razor = RazorTest.new.razor
    ranges.each do |range|
      ips << razor.ipv4_get(range, skip_list, 2)
    end
    ips.sort.should eq([
      "192.168.0.0",
      "192.168.1.0",
    ])
  end

  it "Create specific routes (PoP) in Redis using IPv4/IPv6 ranges" do
    qname = "donatas.net.cdn.example.org"
    extra = {
      :zone => "lt-bnk3.routes.example.org"
    }
    razor_test = RazorTest.new
    redis_unixsocket = razor_test.redis_unixsocket
    razor_zone = razor_test.razor_zone
    razor = razor_test.razor
    redis = Redis.new(unixsocket: redis_unixsocket)
    options = razor.mandatory_dns_options(qname)
    redis.sadd("lt-bnk3.routes.example.org:A", "192.168.0.0/24")
    redis.sadd("lt-bnk3.routes.example.org:AAAA", "2a02:4780:100::/48")
    redis.set(qname, extra[:zone])
    razor.data_from_redis("A", qname, "102.164.115.0", options, extra).first.to_s.should contain("192\.168\.0\.")
    razor.data_from_redis("AAAA", qname, "2a06:4b80::", options, extra).first.to_s.should contain("2a02:4780:0100:")
  end
end
