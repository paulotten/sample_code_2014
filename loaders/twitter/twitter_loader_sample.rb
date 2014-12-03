require 'sequel'
require 'yaml'
require 'twitter'
require 'time'

def getFollowerCount(db, tableName)
	count = Twitter.user[:followers_count]
	time = Time.now

	values = Array.new
	values.push(count)
	values.push(time)
	db[tableName.to_sym].insert(values)
end

# process config file 
config = YAML::load(File.open('twitter_loader.yml'))

# set our twitter credentials
Twitter.configure do | tc |
  tc.consumer_key = config['CONSUMER_KEY']
  tc.consumer_secret = config['CONSUMER_SECRET']
  tc.oauth_token = config['ACCESS_TOKEN']
  tc.oauth_token_secret = config['ACCESS_TOKEN_SECRET']
end

# connect to our database
db = Sequel.connect(config['DATABASE'])

getFollowerCount(db, config['FOLLOWERS'])
