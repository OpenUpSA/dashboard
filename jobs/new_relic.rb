logger = Log4r::Logger.new('new_relic')
logger.outputters << Log4r::StderrOutputter.new('stderr')
logger.outputters[0].formatter = Log4r::SimpleFormatter.new

graphs = {}
graph_data = {}
for api in get_apis
  graphs[api.id] = api.app_id
  graph_data[api.id] = {
    historical: [{x: 0, y: 0}],
    current: 0,
  }
end

SCHEDULER.every '1h', first_in: 0 do
  # get historical points

  now = Time.now
  start_date = now - 8 * 3600 * 24

  graphs.each_pair do |graph_id, app_id|
    logger.info "Getting historical data for #{graph_id} (application #{app_id})"
    newrelic = NewRelic.new(ENV['NEW_RELIC_API_KEY'], app_id)

    points = newrelic.get_values(
      name: 'HttpDispatcher',
      value: 'call_count',
      from: start_date,
      to: now,
      period: 3600*24)
    logger.info "#{graph_id}: Got #{points.length} historical rows"

    data = graph_data[graph_id]
    historical = []

    points.each_with_index do |point, i|
      historical << {
        x: Time.iso8601(point['from']).to_i,
        y: point['values']['call_count']
      }
    end

    data[:historical] = historical
  end
end

SCHEDULER.every '30s', first_in: 0 do
  period = 60*30   # 30 minutes
  now = Time.now
  start_date = now - period

  graphs.each_pair do |graph_id, app_id|

    logger.info "Getting current data for #{graph_id} (application #{app_id})"
    newrelic = NewRelic.new(ENV['NEW_RELIC_API_KEY'], app_id)

    points = newrelic.get_values(
      name: 'HttpDispatcher',
      value: 'call_count',
      from: start_date,
      to: now,
      period: period)

    data = graph_data[graph_id]
    data[:current] = points.first['values']['call_count']

    unless data[:historical].empty?
      send_event(graph_id, points: data[:historical], displayedValue: data[:current])
    end
  end
end
