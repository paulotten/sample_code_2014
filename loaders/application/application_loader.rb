require 'sequel'
require 'yaml'
require 'pp'

def createTable(db, dbLinkNAme, schema, name)
	tableDefinition = "create table " + schema + "." + name + " ("
	first = true
	db["select * from dblink('" + dbLinkNAme + "', 'select column_name, data_type, character_maximum_length from information_schema.columns where table_schema = ''public'' and table_name = ''" + name + "'' order by ordinal_position asc') as t1(column_name text, data_type text, char_length integer)"].all.each do | column |
		columnDefinition = "" + column[:column_name] + " " + column[:data_type]
		
		if(first)
			first = false
		else
			columnDefinition = ", " + columnDefinition
		end

		if(column[:char_length])
			columnDefinition += "(" + column[:char_length].to_s + ")"
		end
		tableDefinition += columnDefinition
	end
	tableDefinition += ")"
	db[tableDefinition].all
	puts "Created table "  + schema + "." + name
end

config = YAML::load(File.open('application_loader.yml'))

# connect to the data warehouse
db = Sequel.connect(config['DATA_WAREHOUSE_DATABASE'])

# manually start a database transaction
db["start transaction"].first

# this link only lasts for the length of the session
# so I don't think it needs to be put in the yaml file 
dbLinkNAme = 'application_database'

# create the database link
db["select dblink_connect_u('" + dbLinkNAme + "', '" + config['APPLICATION_DATABASE'] + "')"].all

# get a list of tables from the remote (application) database
db["select * from dblink('" + dbLinkNAme + "', 'select table_name from information_schema.tables where table_schema=''public''and table_type=''BASE TABLE''') as t1(name text)"].all.each do | tableName |
	name = tableName[:name]
	schema = config['SCHEMA']

	# qualify the table name for the data warehouse
	# (set the schema)
	qualifiedName = Sequel.qualify(schema, name)
	
	# check if the table exists in the datawarehouse
	if(!db.table_exists?(qualifiedName))
		# create the table
		createTable(db, dbLinkNAme, schema, name)
	end

	# build the data structure
	columnNames = Array.new
	columnNamesString = ""
	columnNameWithTypes = ""
	firstColumn = true
	db["select * from dblink('" + dbLinkNAme + "', 'select column_name, data_type from information_schema.columns where table_schema = ''public'' and table_name = ''" + name + "'' order by ordinal_position asc') as t1(column_name text, data_type text)"].all.each do | column |
		if(firstColumn)
			firstColumn = false
		else
			columnNamesString += ", "
			columnNameWithTypes += ", "
		end

		columnNames.push(column[:column_name])
		columnNamesString += column[:column_name]
		columnNameWithTypes += column[:column_name] + " " + column[:data_type]
	end
	# did we find any columns?
	noColumns = firstColumn

	# check if columns (name and data type) don't match
	columnNameWithTypesDW = ""
	firstColumn = true
	db["select column_name, data_type from information_schema.columns where table_schema = '" + schema + "' and table_name = '" + name + "' order by ordinal_position asc"].all.each do | column |
		if(firstColumn)
			firstColumn = false
		else
			columnNameWithTypesDW += ", "
		end
		columnNameWithTypesDW += column[:column_name] + " " + column[:data_type]
	end
	# backup table and recreate it if columns don't match
	if(columnNameWithTypes != columnNameWithTypesDW)
		puts schema + "." + name + "'s columns have changed. Backing it up and recreating it."

		# rename existing table
		db["alter table " + schema + "." + name + " rename to " + name + Date.today.strftime("_%Y_%m_%d")].first
		puts "Renamed " + schema + "." + name + " to " + schema + "." + name + Date.today.strftime("_%Y_%m_%d")

		# recreate table
		createTable(db, dbLinkNAme, schema, name)

		# will need to recreate views somewhere else
	end

	# if the table doesn't have any columns skip it
	if(noColumns)
		puts "" + schema + "." + name + " doesn't have any columns. Skipping."
		next
	end

	# get the last modified date
	lastModifiedColumnName = nil
	lastModifiedDate = nil
	columnNames.each do | column |
		# guess what column has the best date to use
		case column
		when "updated_at", "last_update_date"
			# updated_at is our preference
			lastModifiedColumnName = column
			break
		when "created_at", "history_date"
			# but we'll settle for created_at if we have to
			lastModifiedColumnName = column 
		end
	end
	if(lastModifiedColumnName)
		lastModifiedDate = db["select cast(max(" + lastModifiedColumnName + ") as text) from " + schema + "." + name].first[:max]
	else
		puts "Couldn't figure out the last modified date for " + name + ". Historical data may suffer."
		# if we can't find a last modified date, wipe the table and reload everything
		db["delete from " + schema + "." + name].all
	end

	# load data
	insertString = "insert into " + schema + "." + name + " select * from dblink('" + dbLinkNAme + "', 'select " + columnNamesString + " from " + name
	if(lastModifiedDate)
		insertString += " where " + lastModifiedColumnName + " > ''" + lastModifiedDate + "''"
	end
	insertString += "') as t1(" + columnNameWithTypes + ")"
	db[insertString].all
	puts "Loaded " + schema + "." + name
	puts
end

# close the database link
# it would close automaticly when the database session ends but let's explicitely close it
db["select dblink_disconnect('" + dbLinkNAme + "')"].all

# end database transaction
db["commit"].first

# close connection
db.disconnect