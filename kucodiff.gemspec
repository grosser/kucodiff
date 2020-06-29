name = "kucodiff"
$LOAD_PATH << File.expand_path("../lib", __FILE__)
require "#{name.tr("-", "/")}/version"

Gem::Specification.new name, Kucodiff::VERSION do |s|
  s.summary = "Smart diff for kubernetes configs to ensure symmetric configuration"
  s.authors = ["Michael Grosser"]
  s.email = "michael@grosser.it"
  s.homepage = "https://github.com/grosser/#{name}"
  s.files = `git ls-files lib/ bin/ MIT-LICENSE`.split("\n")
  s.license = "MIT"
  s.required_ruby_version = ">= 2.5.0"
end
