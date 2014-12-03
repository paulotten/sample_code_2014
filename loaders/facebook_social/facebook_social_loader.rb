require 'sequel'
require 'yaml'
require 'fb_graph'
require 'time' # doesn't every thing?
require 'uri'

def processMainPage(pageId, token, db, tableName)
	page = FbGraph::Page.new(pageId).fetch(:access_token => token)

	observedTime = Time.now
	likeCount = page.raw_attributes['likes']
	talkingAboutCount = page.raw_attributes['talking_about_count']

	values = Array.new
	values.push(observedTime)
	values.push(likeCount)
	values.push(talkingAboutCount)
	db[tableName.to_sym].insert(values)
end

def processComments(postId, post, db, tableName)
	post.comments.each do | comment |
		commentId = comment.identifier
		user_id = comment.from.identifier
		user_name = comment.from.name
		message = comment.message
		createdTime = comment.created_time
		likeCount = comment.like_count
		observedTime = Time.now

		values = Array.new
		values.push(postId)
		values.push(commentId)
		values.push(user_id)
		values.push(user_name)
		values.push(message)
		values.push(createdTime)
		values.push(likeCount)
		values.push(observedTime)
		db[tableName.to_sym].insert(values)
	end

	# This will only process the first 25 comments.
	# At time of coding the most comments we have got on a post is only 16.
	# This should perhaps be revisited at a later date.
end

def processPost(postId, token, db, postsTableName, commentsTableName)
	post = FbGraph::Post.new(postId + '?fields=message,link,created_time,updated_time,likes.limit(1).summary(true),shares,comments').fetch(:access_token => token)

	message = post.message

	# ignore posts without messages
	# they seem to be our replies to comments
	if(!message)
		return
	end

	link = post.link
	createdTime = post.created_time
	updatedTime = post.updated_time
	observedTime = Time.now
	likeCount = 0
	shareCount = 0

	if(post.raw_attributes[:likes] && post.raw_attributes[:likes][:summary] && post.raw_attributes[:likes][:summary][:total_count])
		likeCount = post.raw_attributes[:likes][:summary][:total_count]
	end

	# if no one has shared this post then these will be null
	if(post.raw_attributes[:shares] && post.raw_attributes[:shares][:count])
		shareCount = post.raw_attributes[:shares][:count]
	end

	values = Array.new
	values.push(postId)
	values.push(message)
	values.push(link)
	values.push(createdTime)
	values.push(updatedTime)
	values.push(observedTime)
	values.push(likeCount)
	values.push(shareCount)
	db[postsTableName.to_sym].insert(values)

	processComments(postId, post, db, commentsTableName)
	
	puts createdTime
end

# process config file 
config = YAML::load(File.open('facebook_social_loader.yml'))

token = config['ACCESS_TOKEN']
mainPage = config['MAIN_PAGE']
feedLink = mainPage + '/feed'
postExpiry = config['POST_EXPIRY'].to_i
medeoId = config['MEDEO_ID']

# connect to our database
db = Sequel.connect(config['DATABASE'])

mainPageTableName = config['MAIN_PAGE_TABLE_NAME']
postsTableName = config['POSTS_TABLE_NAME']
commentsTableName = config['COMMENTS_TABLE_NAME']

# process our main facebook page
processMainPage(mainPage, token, db, mainPageTableName)

# crawl our feed
feed = FbGraph::Page.new(feedLink).fetch(:access_token => token)
havePostHistory = db[postsTableName.to_sym].count > 0
doneCrawling = false

# process all the posts and comments in the same database transaction
db.transaction do
	while(feed) do
		feed.raw_attributes[:data].each do | post |
			# if we already have historical posts loaded into the database
			# then only prcess the last 7 (or however many) days worth
			if(havePostHistory && Time.parse(post[:created_time]) + postExpiry * 60 * 60 * 24 < Time.now)
				doneCrawling = true
				break
			end

			# we're only interested in our posts
			if(post[:from][:id] == medeoId)
				processPost(post[:id], token, db, postsTableName, commentsTableName)
			end
		end

		if(doneCrawling)
			break
		end

		# get the next page of feed results
		if(!feed.raw_attributes[:paging] || !feed.raw_attributes[:paging][:next])
			break
		end

		# ok a few things are going on here
		# feed.raw_attributes[:paging][:next] is us finding the next page of posts for our feed
		# fb_graph automaticly includes the 'https://graph.facebook.com/' however which causes an error
		# so I wrap it in a URI object and call .path and .query on it
		# this throws an invalid url error however due to a pipe (|) character in the url
		# so I encoded that as '%7C'
		uri = URI(feed.raw_attributes[:paging][:next].gsub('|', '%7C'))
		nextPage = uri.path + '?' + uri.query

		feed = FbGraph::Page.new(nextPage).fetch(:access_token => token)
	end
end
