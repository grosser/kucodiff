require "spec_helper"

SingleCov.covered!

describe Kucodiff do
  it "has a VERSION" do
    expect(Kucodiff::VERSION).to match(/^[\.\da-z]+$/)
  end
end
