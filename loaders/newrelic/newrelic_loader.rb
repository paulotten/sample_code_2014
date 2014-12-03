# Gets a list of available metrics from newrelic. Creates 10 worker threads to pull down these metrics. Saves metrics to database.

require 'nokogiri'
require 'open-uri'
require 'thread'
require 'cgi' # only used to escape a query parameter
require 'sequel'
require 'yaml'

config = YAML::load(File.open('newrelic_loader.yml'))

# connection info for our database
DBConnString = config['DATABASE']

# newrelic info
baseUrl = config['BASE_URL']
$apiKey = config['API_KEY']

$i = 0
$j = 0
$mu1 = Mutex.new
$mu2 = Mutex.new
$uriList = Array.new

# simple helper method for querying newrelic
#
# retries failed connections
# failed connection are rare (99.999+% success rate)
# but this loader makes over 20,000 requests each run so it occassionally sees one (twice by my memory)
def queryNewrelic(baseUrl)
    returnable = nil
    retries = 0
    maxRetries = 5 # exessive

    while(true)
        begin
            returnable = Nokogiri::HTML(open(baseUrl, "x-api-key" => $apiKey))
            break
        rescue Exception => msg 
            puts msg
            retries += 1

            if(retries > maxRetries)
                raise 'Too many retries.'
            end

            sleep 3 # back off and give the network a few seconds to settle down
        end
    end

    return returnable
end

# work function, retrieves individual metrics
def work
    go = true
    
    while go do
        taskId = 0
        temp = Array.new
        
        $mu1.synchronize {
            taskId = $j
            
            $j += 1
            
            if($j > $i)
                go = false
            end
        }
        if !go
            break
        end
        
        xml = queryNewrelic($uriList[taskId])
        
        xml.xpath("//metric").each do |metric|
            metric.xpath(".//field").each do |field|
                metricName      = metric.attribute("name")
                metricBegin     = metric.attribute("begin")
                metricEnd       = metric.attribute("end")
                metricApp       = metric.attribute("app")
                metricAgentId   = metric.attribute("agent_id")
                fieldName       = field.attribute("name")
                fieldValue      = field.content
                temp.push([metricName, metricBegin, metricEnd, metricApp, metricAgentId, fieldName, fieldValue])
            end
        end
        
        $mu2.synchronize {
            temp.each do | row |
                if(row[6].to_s != '')
                    $dataset.insert(:metric_name => row[0].to_s, :metric_begin => row[1].to_s, :metric_end => row[2].to_s, :metric_app => row[3].to_s, :metric_agent_id => row[4].to_s, :field_name => row[5].to_s, :field_value => row[6].to_s)
                else
                    $dataset.insert(:metric_name => row[0].to_s, :metric_begin => row[1].to_s, :metric_end => row[2].to_s, :metric_app => row[3].to_s, :metric_agent_id => row[4].to_s, :field_name => row[5].to_s)
                end
            end
            puts "Retrieved metric #" + taskId.to_s
        }
    end
end

# test that my retry logic works
#queryNewrelic("https://127.0.0.1:9123") # should fail

# get a list of availible metrics
uri = URI(baseUrl + "metrics.xml")
metricsList = queryNewrelic(uri)

# create a list of uri's to retrieve metrics
today = Time.new
yesterday = today - (60*60*24*1)
td = today.day.to_s
tm = today.month.to_s
ty = today.year.to_s
yd = yesterday.day.to_s
ym = yesterday.month.to_s
yy = today.year.to_s
metricsList.xpath("//metric").each do |metric|
    metric.xpath(".//field").each do |field|
        temp = baseUrl + "data.xml?metrics[]=" + CGI::escape("" + metric.attribute("name")) + "&field=" + field.attribute("name") + "&begin=" + yy + "-" + ym + "-" + yd + "T00:00:00Z&end=" + ty + "-" + tm + "-" + td + "T00:00:00Z"
        $uriList[$i] = temp
        
        $i += 1
    end
end
puts $i.to_s + " metrics to retrieve..."

DB = Sequel.connect(DBConnString)
$dataset = DB[:newrelic_exports]
DB.transaction do # do all this in single database transaction so we fallback cleanly if something fails
    # setup up the worker threads
    threadList = Array.new
    for k in 0..10
        threadList[k] = Thread.new{work()}
    end
    # wait for them
    threadList.each do |t|
        t.join
    end
end
