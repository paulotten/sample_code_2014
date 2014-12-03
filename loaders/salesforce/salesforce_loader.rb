require 'databasedotcom'
require 'sequel'
require 'yaml'

config = YAML::load(File.open('salesforce_loader.yml'))

# connection info for our database
DBConnString = config['DATABASE']
schema = config['SCHEMA']

# salesforce connection info
clientId = config['CLIENT_ID']
clientSecret = config['CLIENT_SECRET']
host = config['HOST']
username = config['USERNAME']
password = config['PASSWORD']
userSecret = config['USER_SECRET']

# .all doesn't actually page through all the objects. So we'll do it ourselves
def getAll(objs)
	returnable = Array.new
	returnable += objs
	
	while(objs.next_page?)
		objs = objs.next_page
		returnable += objs
	end

	return returnable
end

# sequel's table_exists? method creates an SQL error if the table doesn't exist, that breaks the transaction
# this implementation isn't as generic but won't break the transaction
def tableExists?(db, schema, name)
	exist = db["select * from information_schema.tables where table_schema = '" + schema + "' and table_name = '" + name +"'"].first

	return exist != nil
end

# initial dataload: pulls all the records from salesforce, creates a table, inserts all the records into the table  
def initialLoad(client, db, objectName, tableName)
	puts "Initial load of " + objectName + " objects"
	objs = client.materialize(objectName)

	all_objs = getAll(objs.all)

	if(objs.count == 0)
		puts "No data to load, skipping"
	else
		tableCreated = false
		all_objs.each do | obj |
			if(!tableCreated)
				# create the table
				db.create_table(tableName)
				tableCreated = true

				objs.first.attributes.each do | attribute |
					# puts attribute[0] # name
					# puts objs.field_type(attribute[0]) # type
					# puts attribute[1] # value

					dataType = nil
					onlyTime = false
					case objs.field_type(attribute[0])
					when "string", "id", "reference", "picklist", "textarea", "multipicklist", "email", "base64", "phone", "anyType", "combobox", "url"
						dataType = String
					when "boolean"
						dataType = TrueClass
					when "double", "percent", "currency"
						dataType = Float
					when "date"
						dataType = Date
					when "datetime"
						dataType = DateTime
					when "int"
						dataType = Integer
					when "time"
						dataType = Time
						onlyTime = true
						
					else
						puts "Unknown type: " + objs.field_type(attribute[0]) + ", treating it as a String"
						dataType = String
					end

					db.alter_table(tableName) do
						add_column(attribute[0], dataType, :only_time=>onlyTime)
					end
				end
			end

			# insert a row for the object
			row = Array.new
			obj.attributes.each do | attribute |
				row.push(attribute[1]) # add value
			end
			db[tableName].insert(row)
		end
	end
	puts "Done"
end

def columnsMatch?(a, b)
	if(a.size != b.size)
		return false
	end

	i = 0
	while(i < a.size)
		if(a[i] != b[i])
			return false
		end
		i += 1
	end

	return true
end

# gets the last modified date from our database, asks salesforce for everything newer
def getUpdates(client, db, objectName, tableName, schema, unqualifiedTableName)
	puts "Getting updates for " + objectName + " objects"

	# get last modified date
	dataset = db[tableName]
	columnName = nil # different salesforce objects have different names for the last modified date
	dataset.columns.each do | column |
		case column
		when :LastModifiedDate, :LastUpdate, :SystemModstamp
			columnName = column
			break
		when :CreatedDate, :StartDate, :LoginTime
			columnName = column
			# creation dates are our least preferred indicator, only use them if we can't find a better
		end
	end
	if(columnName != nil)
		lastModified = dataset.max(columnName)

		# get updated objects from salesforce
		objs = client.materialize(objectName)
		newObjs = objs.query("" + columnName.to_s + " > " + lastModified.to_s.sub(" ", "T").sub(" ", ""))
		# "2013-10-22 16:38:06 -0700" should be "2013-10-22T16:38:06-0700"

		newObjs = getAll(newObjs)

		# check for salesforce schema changes
		# I'd do this earlier but that would generate additional API calls which Salesforce limits us on
		dwColumns = Array.new
		sfColumns = Array.new
		dataset.columns.sort.each do | column |
			dwColumns.push(column.to_s)
		end
		if(!newObjs.first)
			puts "Done (no new data to load)"
			return
		end
		newObjs.first.attributes.sort.each do | attribute |
			sfColumns.push(attribute[0].to_s)
		end
		if(!columnsMatch?(dwColumns, sfColumns))
			puts "Column mismatch detected. Backing up and recreating table"

			name = unqualifiedTableName

			db["alter table " + schema + "." + name + " rename to " + name + Date.today.strftime("_%Y_%m_%d")].first
			puts "Renamed " + schema + "." + name + " to " + schema + "." + name + Date.today.strftime("_%Y_%m_%d")

			puts "Recreating table"
			initialLoad(client, db, objectName, tableName)

			# views will need to be recreated elsewhere

			return
		end

		# insert a rows for the updated objects
		newObjs.each do | obj |
			row = Array.new
			obj.attributes.each do | attribute |
				row.push(attribute[1])
			end
			db[tableName].insert(row)
		end
		puts "Done"
	else
		raise "Failed: couldn't figure out the last modified date"
	end
end

# force an update for a give object type
# drops the corresponding table and recreates it
def forceUpdate(client, db, objectName, tableName)
	puts "Forcing an update of " + objectName + " objects"

	db.drop_table(tableName)
	initialLoad(client, db, objectName, tableName)
end

# connect to salesforce
client = Databasedotcom::Client.new(:client_id => clientId, :client_secret => clientSecret, :host => host)
client.authenticate(:username => username, :password => "" + password + userSecret)

# connect to our database
db = Sequel.connect(DBConnString)

# sql logging
# db.logger = Logger.new($stdout)

# manually start a database transaction
db["start transaction"].first

# figure out what we can pull from salesforce
client.list_sobjects.each do | objectName |
	# some salesforce objects can't be queried, skip them
	case objectName
	when "ActivityHistory", "AggregateResult", "EmailStatus", "Name", "NoteAndAttachment",
		"OpenActivity", "ProcessInstanceHistory", "Vote"
		# "Vote" can be queried but you have to specify some criteria so lets just skip it
		next
	end

	unqualifiedTableName = objectName.downcase.gsub("__", "_") # sequel treats double underscores as schema qualifiers
	tableName = Sequel.qualify(schema, unqualifiedTableName)

	if(!tableExists?(db, schema, unqualifiedTableName))
		initialLoad(client, db, objectName, tableName)
	else
		case objectName
		when "DashboardComponent"
			# some salesforce objects don't have dates
			# we have to fetch all of them each time
			forceUpdate(client, db, objectName, tableName)
		else
			getUpdates(client, db, objectName, tableName, schema, unqualifiedTableName)
		end
	end
	puts
end

# commit transaction
db["commit"].first
