require 'google/api_client'
require 'json'
require 'sequel'
require 'yaml'

config = YAML::load(File.open('google_analytics_loader.yml'))

# connection info for our database
DBConnString = config['DATABASE']

def getPageViews(client, ga, viewId, viewName, db, tableName, metrics, dimenstions, config)
	# bind the table we will be using
	dataset = db[tableName.to_sym]

	# set a start date to use if we have never loaded googla analytics data into this database
	defaultStartDate = config['DEFAULT_START_DATE']
	
	# get the last day we have page views for, otherwise use our default start date
	startDate = dataset.where(config['COLUMN_VIEW_NAME'].to_sym => viewName).max(config['COLUMN_VISIT_DATE'].to_sym)
	if(startDate == nil)
		startDate = Date.parse(defaultStartDate)
	end
	date = startDate + 1

	# get data for up to and including yesterday
	# (today's data will not be complete until tomorrow)
	while(date < Date.today) do
		dateString = "%04d-%02d-%02d" % [date.year, date.month, date.day]
		puts viewName + ":" + dateString
		
		# build initial request
		request = Google::APIClient::Request.new(
			:api_method => ga.data.ga.get,
			:parameters => {
				'ids' => viewId,
				'start-date' => dateString,
				'end-date' => dateString,
				'metrics' => metrics,
				'dimensions' => dimenstions
			}
		)

		# begin a database transaction
		# either the entire day gets committed or none of it does
		db.transaction do
			while (request != nil) do
				# query google analytics
				result = client.execute(request)
				
				# check if google analytics is sampling our data
				if(result.data["containsSampledData"].to_s == "true")
					puts "Google Analytics returned sampled data. This will probably reduce its accuracy."
				end

				# save the data from google analytics to our database
				result.data["rows"].each do | row |
					values = Array.new
					values.push(viewName)
					values.push(dateString)
					row.each do | value |
						values.push(value)
					end
					dataset.insert(values)
				end

				# if google analytics has more pages of results for us request them too
				#
				# result.next_page_token seems to be broken for google analytics
				# https://github.com/google/google-api-ruby-client/issues/77
				#
				# lets try pulling the next page url out manually
				if(result.data['nextLink'] != nil)
					request = Google::APIClient::Request.new(uri: result.data['nextLink'])
				else
					request = nil
					break
				end
			end
		end

		date = date + 1
	end
end

# authenticate
client = Google::APIClient.new(:application_name => config['APPLICATION_NAME'], :application_version => config['APPLICATION_VERSION'])
key = Google::APIClient::KeyUtils.load_from_pkcs12(config['KEY_PATH'], config['KEY_PASSWORD'])
client.authorization = Signet::OAuth2::Client.new(
	:token_credential_uri => config['TOKEN_CREDENTIAL_URI'],
	:audience => config['AUDIENCE'],
	:scope => config['SCOPE'],
	:issuer => config['KEY_ISSUER'],
	:signing_key => key)
client.authorization.fetch_access_token!

# find the analytics service
ga = client.discovered_api(config['API_NAME'], config['API_VERSION'])

# connect to our database
db = Sequel.connect(DBConnString)

# retrieve pageviews
getPageViews(client, ga, config['ALL_SITES_VIEW_ID'], config['ALL_SITES_VIEW_NAME'], db, config['TABLE_NAME_1'], config['METRICS'], config['DIMENSIONS_1'], config)
getPageViews(client, ga, config['ALL_SITES_VIEW_ID'], config['ALL_SITES_VIEW_NAME'], db, config['TABLE_NAME_2'], config['METRICS'], config['DIMENSIONS_2'], config)
