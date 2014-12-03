class ApplicationController < ActionController::Base
  protect_from_forgery

  protected
    def dbConnect()
      Sequel.default_timezone = :utc # Rails saves times as UTC, make Sequel do the same
      Sequel.datetime_class = Time # Don't strictly need to set, if we ever set this differently somewhere else this will catch it

      connString = YAML.load_file("./config/sequel.yml")['DATABASE']

      return Sequel.connect(connString)
    end

    def getUnit
      unit = params['unit']

      if(!unit)
        unit = 'week'
      end

      return unit
    end

    # filters rows from a table/view by unit of time and time frame
    # caches for 1 hour (parameters must match exactly) 
    def filter(tableName, dateCol)
      unit = getUnit
      db = dbConnect

      begin
        if(params['start_date'] && Time.parse(params['start_date']))
          fromDate = params['start_date']
        end
      rescue ArgumentError
        # start_date param is not parsable, don't use it
      end

      begin
        if(params['end_date'] && Time.parse(params['end_date']))
          toDate = params['end_date']
        end
      rescue ArgumentError
        # end_date param is not parsable, don't use it
      end

      returnable = Rails.cache.fetch('' + tableName.to_s + ':' + unit + ':' + fromDate.to_s + ',' + toDate.to_s, expires_in: 1.hour, force: false) do

        dataset = db[tableName].where(:unit => unit)
        if(fromDate)
          dataset = dataset.where(dateCol.to_s + ' >= ?', fromDate)
        end
        if(toDate)
          dataset = dataset.where(dateCol.to_s + ' <= ?', toDate)
        end

        returnable = dataset.all
        db.disconnect

        returnable
      end

      return returnable
    end

    # returns all rows from a table/view
    # caches for 1 hour
    def allRows(tableName)
      dataset = Rails.cache.fetch(tableName.to_s + ':allRows', expires_in: 1.hour) do
        db = Sequel.connect(YAML.load_file("./config/sequel.yml")['DATABASE'])
        dataset = db[tableName].all
        db.disconnect
        dataset
      end

      return dataset
    end
    helper_method :allRows
end
