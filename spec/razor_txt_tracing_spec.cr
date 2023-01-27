require "./helper"

describe "Tracing" do
  it "Check if the continent and the country are returned from EDNS" do
    qname = "donatas2.net.cdn.example.org"
    razor = RazorTest.new.razor
    options = razor.mandatory_dns_options(qname)
    razor.data_from_redis("TXT", qname, "32.47.115.0", options).should eq(["Razor/32.47.115.0 (NA:US)/10.0.2.1"])
  end

  it "Check if source and destinationed IPs are returned from EDNS" do
    qname = "donatas1.net.cdn.example.org"
    razor = RazorTest.new.razor
    options = razor.mandatory_dns_options(qname)
    razor.data_from_redis("TXT", qname, "32.47.115.0", options).should eq(["Razor/32.47.115.0/10.0.1.2"])
  end
end
