require 'sinatra/base'
require 'redis'
require 'json'
require 'csv'
require 'httparty'
require 'active_support/all'
require 'geocoder'

require 'dotenv'
Dotenv.load

$url = "https://docs.google.com/spreadsheet/pub?key=0AvYMScvV9vpcdHBkbUxfX2N2ZmdiVXhQU3ltelpoRkE&single=true&gid=1&output=csv"

if !ENV['REDISCLOUD_URL'].nil?
	redis_connection_string = ENV["REDISCLOUD_URL"] 
end

if ENV['REMOTE_REDIS'] == "true"
	redis_connection_string =`heroku config | grep REDIS`.split(":")[1..-1].join(":").strip #TODO: ugly
end

if !redis_connection_string.nil?
		puts "connecting to #{redis_connection_string}"
        uri = URI.parse(redis_connection_string)
        $redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
else
		puts "connecting to local redis"
        $redis = Redis.new
end

class App < Sinatra::Base

	get '/' do
		erb :index
	end

	get '/geocode_queue' do
		$redis.smembers('geocode_queue').to_json
	end

	get '/geocode_one' do
		address = $redis.smembers('geocode_queue').first
		result = Geocoder.search(address).first
		latlng = result.data['geometry']['location']
		$redis.hset('geocoded', address, latlng.to_json)
		$redis.srem('geocode_queue', address)
		$redis.lpush('geocoder_results', {address: address, latlng: latlng}.to_json)
		[address, latlng].to_json
	end

	get '/geocode_cache' do
		$redis.hgetall('geocoded').to_json
	end

	get '/pull_data' do
		
		response = HTTParty.get($url)
		content_type "application/json"
		CSV.parse(response.body, :headers => true).map{|line|
			record = line.to_hash.inject({}){|obj, item|
				obj[item.first.downcase.strip.gsub('?', '').gsub(/[^a-z]/, "_").downcase] = item.last # this is ugly. basically, wrangle the ugly column header into a decent key
				obj
			}
			if !record['did_your_power_go_out'].nil?
				record['status'] = 'Still Out' 			   if record['did_your_power_go_out'].include?('still out')
				record['status'] = 'No (never was)'        if record['did_your_power_go_out'].include?('No')
				record['status'] = 'No (it was earlier)'   if record['did_your_power_go_out'].include?('back on now')
				
				clean_address = record['where_do_you_live'].gsub("&", "and") + ", Eugene, Oregon"				
				clean_address.downcase! # normalize, hopefully more cache hits this way
				record['address_cleaned'] = clean_address

				geocoded_address = $redis.hget("geocoded", clean_address)
				if geocoded_address.nil?
					record['geocoded'] = nil
					$redis.sadd('geocode_queue', clean_address)
				elsif geocoded_address == 'INVALID'
					record['geocoded'] = 'INVALID' # some address wont be geocoded
				else
					record['geocoded'] = JSON.parse(geocoded_address)
				end
			end

			record

		}.to_json
		
	end
end
