$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), "lib")))

require "rubygems"
require "geminabox"
Geminabox.data = File.expand_path('./vendor/gems', File.dirname(__FILE__))

qs_gems_password = ENV['QS_GEMS_PASSWORD'].freeze

raise "No password set" unless qs_gems_password

use Rack::Auth::Basic, "Gems" do |username, password|
  qs_gems_password == password
end

run Geminabox
