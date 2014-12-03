require 'gruff'
require 'sequel'
require 'time'

class GraphsController < ApplicationController

  def index
  end

  # 150 LINES REDACTED HERE

  private

    def getExpiry()
      # cache image browser side until 2am
      # loaders start fetching new data at 1am, should be done well before 2am
      cacheTill = 2 # 2am
      expiryDay = Time.now().hour < cacheTill ? Date.today : Date.today + 1
      expiry = (expiryDay.to_time + cacheTill.hours).httpdate()
    end

    def histogram(tableName, indexCol, nameCol, valueCol, title, param1 = nil, param2 = nil)
      db = dbConnect
      dataset = nil
      if(param2 != nil)
        dataset = db[tableName, param1, param2].all
      elsif(param1 != nil)
        dataset = db[tableName, param1].all
      else
        dataset = db[tableName].all
      end
      db.disconnect

      data = Array.new
      labels = Hash.new

      count = dataset.size
      last = count - 1
      max = 1

      i = 0
      dataset.each do | row |
        data.push(row[valueCol])

        if(row[valueCol] > max)
          max = row[valueCol]
        end

        if(count < 6 || # if we have 5 or less points label all of them
           i == 0 || i == last || i == count / 2 || # always label the first, middle, and last point
           (count > 8 && (i == count / 4 ||  i == count * 3 / 4)) # label 1/4 and 3/4 points if we have enough data
          )
          labels[i] = row[nameCol]
        end
        i += 1
      end

      # give Gruff a hint about what we want our maximum value to be so it doesn't give us something fractional
      if(max > 1)
        max = max.to_f.ceil
        max += max%2
      end

      g = Gruff::Bar.new
      g.title = title
      g.maximum_value = max
      g.minimum_value = 0
      g.hide_legend = true

      g.data('', data)
      g.labels = labels

      response.headers["Expires"] = getExpiry()
      send_data(g.to_blob, :filename => 'graph.png', :type => 'image/png', :disposition=> 'inline')
    end

    def scatterGraph(tableName, dateCol, xCol, yCol, title)
      dataset = filter(tableName, dateCol)

      x = Array.new
      y = Array.new

      max = 1

      dataset.each do | row |
        x.push(row[xCol])
        y.push(row[yCol])

        if(row[yCol] != nil and row[yCol] > max)
          max = row[yCol]
        end
      end

      # give Gruff a hint about what we want our maximum value to be so it doesn't give us something fractional
      if(max > 1)
        max = max.to_f.ceil
        max += max%2
      end

      g = Gruff::Scatter.new
      g.title = title
      g.maximum_value = max
      g.minimum_value = 0
      g.hide_legend = true

      if(dataset.size > 0)
        g.data('', x, y)
      end

      response.headers["Expires"] = getExpiry()
      send_data(g.to_blob, :filename => 'graph.png', :type => 'image/png', :disposition=> 'inline')
    end

    def graph(tableName, dateCol, valueCol, title, opts = {})
      opts = {
        nameCol: nil,
        cumulative: false,
        nilToZero: true,
        multiColumnHash: nil,
        sortNames: true,
        graphType: nil
      }.merge(opts)
      
      nameCol = opts[:nameCol]
      cumulative = opts[:cumulative]
      nilToZero = opts[:nilToZero]
      multiColumnHash = opts[:multiColumnHash]
      sortNames = opts[:sortNames]
      graphType = opts[:graphType]

      # allow url parameters to override our default graph type
      if(params['graph_type'] != nil && params['graph_type'] != '')
        graphType = params['graph_type']
      end

      # most graph types don't support nulls, convert them to zero if using such a graph
      if(graphType == 'Bar' || graphType == 'StackedBar' || graphType == 'StackedArea' ||
         graphType == 'Dot' || graphType == 'SideBar' || graphType == 'SideStackedBar'
        )
        nilToZero = true
      end

      unit = getUnit()
      dataset = filter(tableName, dateCol)

      names = Hash.new
      dates = Hash.new
      max = 1

      dataset.each do | row |
        if(multiColumnHash != nil)
          multiColumnHash.each_key do | name |
            if(!names[name])
              names[name] = 0
            end
            
            if(!dates.has_key?(row[dateCol]))
              dates[row[dateCol]] = Hash.new
            end
            dates[row[dateCol]][name] = row[multiColumnHash[name]]
          end
        else
          if(nameCol != nil)
            name = row[nameCol]
          else
            name = 'dummy'
          end

          if(!names[name])
            names[name] = 0
          end

          if(!dates.has_key?(row[dateCol]))
            dates[row[dateCol]] = Hash.new
          end
          dates[row[dateCol]][name] = row[valueCol]
        end
      end

      data = Hash.new
      labels = Hash.new
      i = 0

      count = dates.keys.size
      last = count - 1

      # on horizontal graphs fake a tick mark (') at the center of the column
      # on vertical graphs don't
      prepend = ''
      if(graphType != 'Dot' && graphType != 'Net' && graphType != 'SideBar' && graphType != 'SideStackedBar')
        prepend = '\'\n'
      end

      dates.each_key do | date |
        if(count < 6 || # if we have 5 or less points label all of them
           i == 0 || i == last || i == count / 2 || # always label the first, middle, and last point
           (count > 8 && (i == count / 4 ||  i == count * 3 / 4)) || # label 1/4 and 3/4 points if we have enough data
           graphType == 'Net' # Net graphs display a label for every point, might as well provide one
          )
          if(unit == 'hour' || unit == 'minute')
            labels[i] = date.strftime('%Y-%m-%d\n%H:%M')
          elsif(unit == 'year')
            labels[i] = date.strftime(prepend + '%Y')
          elsif(unit == 'month' || unit == 'quarter')
            labels[i] = date.strftime(prepend + '%Y-%m')
          else
            labels[i] = date.strftime(prepend + '%Y-%m-%d')
          end
        end

        i += 1

        names.each_key do | name |
          if(name)
            value = dates[date][name]

            if(!data[name])
              data[name] = Array.new
            end

            if(nilToZero || cumulative)          
              if(!value)
                value = 0
              end
            end

            if(cumulative)
              names[name] += value
              data[name].push(names[name])

              if(names[name] != nil && names[name] > max)
                max = names[name]
              end
            else
              data[name].push(value)

              if(value != nil && value > max)
                max = value
              end
            end
          end
        end
      end

      # give Gruff a hint about what we want our maximum value to be so it doesn't give us something fractional
      if(max > 1)
        max = max.to_f.ceil
        max += max%2
      end

      g = nil
      if(graphType == 'Bar')
        g = Gruff::Bar.new
      elsif(graphType == 'StackedBar')
        g = Gruff::StackedBar.new
      elsif(graphType == 'StackedArea')
        g = Gruff::StackedArea.new
      elsif(graphType == 'Dot')
        g = Gruff::Dot.new
      elsif(graphType == 'Net')
        g = Gruff::Net.new
      elsif(graphType == 'SideBar')
        g = Gruff::SideBar.new
      elsif(graphType == 'SideStackedBar')
        g = Gruff::SideStackedBar.new
      else
        g = Gruff::Line.new
      end
      
      g.title = title
      g.maximum_value = max
      g.minimum_value = 0
      g.labels = labels

      if(nameCol == nil && multiColumnHash == nil)
        g.hide_legend = true
      end

      if(multiColumnHash == nil)
        if(sortNames)
          list = data.keys.sort
        else
          list = data.keys
        end
        list.each do | key |
          g.data(key, data[key])
        end
      else
        data.keys.each do | key |
          g.data(key, data[key])
        end
      end
      
      response.headers["Expires"] = getExpiry()
      send_data(g.to_blob, :filename => 'graph.png', :type => 'image/png', :disposition=> 'inline')
    end

end