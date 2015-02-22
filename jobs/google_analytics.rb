require 'google/api_client'
require 'log4r'

logger = Log4r::Logger.new('ga')
logger.outputters << Log4r::StderrOutputter.new('stderr')
logger.outputters[0].formatter = Log4r::SimpleFormatter.new

google_account_id = '301981928719-8l5uovftgnct3fqltt6r8k2ut25o4tp8@developer.gserviceaccount.com'

# setup the client
client = Google::APIClient.new
key = Google::APIClient::KeyUtils.load_from_pem(ENV['GOOGLE_API_KEY'].gsub('\n', "\n"), 'notasecret')
client.authorization = Signet::OAuth2::Client.new(
  :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
  :audience => 'https://accounts.google.com/o/oauth2/token',
  :scope => 'https://www.googleapis.com/auth/analytics',
  :issuer => google_account_id,
  :signing_key => key)
logger.info "Setting up Google Analytics Client"
client.authorization.fetch_access_token!
ga = client.discovered_api('analytics', 'v3') 
logger.info "Client ready"

graphs = {}
graph_data = {}
for website in get_websites
  graphs[website.id] = website.tracking_id
  graph_data[website.id] = {
    historical: [],
    current: 0,
  }
end

# walk through accounts and match tracking IDs to property IDs
logger.info "Mapping tracking IDs to property IDs"
for account in client.execute(api_method: ga.management.accounts.list).data.items
  response = client.execute(api_method: ga.management.webproperties.list, parameters: {accountId: account.id})

  if response.error?
    logger.error response.error_message
  elsif response.data
    graphs.each_pair do |graph_id, tracking_id|
      for property in response.data.items
        if property.id == tracking_id
          graphs[graph_id] = property.defaultProfileId
          break
        end
      end
    end
  end
end

# sanity check
graphs.each_pair do |graph_id, tracking_id|
  if tracking_id =~ /^UA-/
    raise ArgumentError.new("Couldn't map tracking id #{tracking_id} to a web property for graph #{graph_id}. Check permissions on the Google Analytics account and the tracking id.")
  end
end

SCHEDULER.every '1h', first_in: 0 do
  # get historical points

  now = Time.now
  start_date = now - 7 * 3600 * 24

  graphs.each_pair do |graph_id, property_id|
    logger.info "Getting historical data for #{graph_id} (property #{property_id})"

    response = client.execute(api_method: ga.data.ga.get, parameters: {
      ids: "ga:#{property_id}",
      'start-date' => start_date.strftime('%Y-%m-%d'),
      'end-date' => now.strftime('%Y-%m-%d'),
      metrics: 'ga:sessions',
      dimensions: 'ga:date',
    })

    if response.error?
      logger.error "#{graph_id}: #{response.error_message}"
    elsif response.data?
      logger.info "#{graph_id}: Got #{response.data.rows.length} historical rows"

      data = graph_data[graph_id]
      historical = []

      response.data.rows.each_with_index do |row, i|
        historical << {
          x: Time.parse(row[0]).to_i,
          y: row[1].to_i
        }
      end

      data['historical'] = historical
    end
  end
end

SCHEDULER.every '30s', first_in: 0 do
  # get current users on site

  graphs.each_pair do |graph_id, property_id|
    response = client.execute(api_method: ga.data.realtime.get, parameters: {
      ids: "ga:#{property_id}",
      metrics: 'rt:activeUsers'
    })

    if response.error?
      logger.error "#{graph_id}: realtime data error: #{response.error_message}"
    elsif response.data?
      data = graph_data[graph_id]

      if response.data.totalResults > 0
        data['current'] = response.data.rows[0][0].to_i
      else
        data['current'] = 0
      end
    end

    send_event(graph_id, points: data['historical'], displayedValue: data['current'])
  end
end
