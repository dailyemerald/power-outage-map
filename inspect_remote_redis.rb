require 'redis'
require 'uri'
require 'json'
print "connecting..."
uri = URI.parse(`heroku config | grep REDIS`.split(":")[1..-1].join(":").strip)
redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
print "done "
puts redis.info['used_memory_human']
puts redis.get('views_total')
redis.monitor {|line|
	puts line
}
