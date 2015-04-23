require 'time'
require 'rest-client'

class NewRelic
  def initialize(api_key, app_id)
    @url = "https://api.newrelic.com/v2/applications/#{app_id}/metrics/data.json"
    @headers = {'X-Api-Key' => api_key}
  end

  def get_values(options)
    params = {
      'names[]' => options[:name],
      'values[]' => options[:value],
      'summarize' => 'false',
    }

    params['from'] = options[:from].iso8601 if options[:from]
    params['to'] = options[:to].iso8601 if options[:to]
    params['period'] = options[:period] if options[:period]

    _get(params)['metric_data']['metrics'][0]['timeslices']
  end

  def _get(params)
    params = {params: params}
    params.update(@headers)
    JSON.parse(RestClient.get(@url, params))
  end
end
