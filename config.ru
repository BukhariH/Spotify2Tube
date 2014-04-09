require 'rubygems'
require 'bundler'

Bundler.require :default, (ENV["RACK_ENV"] || "development").to_sym

# ENV['MEMCACHE_SERVERS'] = "localhost"
if memcache_servers = ENV['MEMCACHE_SERVERS']
  use Rack::Cache,
    verbose: true,
    metastore:   "memcached://#{memcache_servers}",
    entitystore: "memcached://#{memcache_servers}"
end

require './app.rb'
run Spotyt.new