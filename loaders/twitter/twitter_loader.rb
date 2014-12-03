require 'sequel'
require 'yaml'
require 'twitter'
require 'time'
require 'cgi' # used for decoding tweets

def getFollowerCount(db, tableName)
	count = Twitter.user[:followers_count]
	time = Time.now

	values = Array.new
	values.push(count)
	values.push(time)
	db[tableName.to_sym].insert(values)
end

def processSearch(query, db, tableName)
	results = Twitter.search(query, :count => 100, :result_type => "recent").results

	observedTime = Time.now

	db.transaction do
		havePostHistory = db[tableName.to_sym].count > 0

		results.each do | result |
			id = result.id.to_s
			createdAt = result.created_at
			userId = result.user.id.to_s
			userScreenName = result.user.screen_name
			text = CGI.unescapeHTML(result.text)
			retweetCount = result.retweet_count
			favoriteCount = result.favorite_count

			values = Array.new
			values.push(id)
			values.push(createdAt)
			values.push(userId)
			values.push(userScreenName)
			values.push(text)
			values.push(retweetCount)
			values.push(favoriteCount)
			values.push(observedTime)
			db[tableName.to_sym].insert(values)
		end
	end
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

processSearch('from:medeo', db, config['SENT'])
processSearch('@medeo', db, config['MENTION'])
processSearch('medeo', db, config['SEARCH'])