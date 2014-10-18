require 'google/api_client'

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
client.authorization.fetch_access_token!
ga = client.discovered_api('analytics', 'v3') 

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
for account in client.execute(api_method: ga.management.accounts.list).data.items
  response = client.execute(api_method: ga.management.webproperties.list, parameters: {accountId: account.id})

  if response.data
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
    response = client.execute(api_method: ga.data.ga.get, parameters: {
      ids: "ga:#{property_id}",
      'start-date' => start_date.strftime('%Y-%m-%d'),
      'end-date' => now.strftime('%Y-%m-%d'),
      metrics: 'ga:sessions',
      dimensions: 'ga:date',
    })

    if response.data?
      data = graph_data[graph_id]
      data['historical'] = []

      response.data.rows.each_with_index do |row, i|
        data['historical'] << {
          x: Time.parse(row[0]).to_i,
          y: row[1].to_i
        }
      end
    end
  end
end

SCHEDULER.every '10s', first_in: 0 do
  # get current users on site

  graphs.each_pair do |graph_id, property_id|
    response = client.execute(api_method: ga.data.realtime.get, parameters: {
      ids: "ga:#{property_id}",
      metrics: 'rt:activeUsers'
    })

    if response.data?
      data = graph_data[graph_id]

      if response.data.totalResults > 0
        data['current'] = response.data.rows[0][0].to_i
      else
        data['current'] = 0
      end
    end
  end
end

SCHEDULER.every '2s', first_in: 0 do
  graph_data.each_pair do |graph_id, data|
    send_event(graph_id, points: data['historical'], displayedValue: data['current'])
  end
end
