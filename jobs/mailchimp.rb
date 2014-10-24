require 'mailchimp'

# setup the client
mailchimp = Mailchimp::API.new(ENV['MAILCHIMP_API_KEY'])

SCHEDULER.every '1h', first_in: 0 do
  # get current subscribers
  info = mailchimp.lists.list({list_name: 'Naked Data'})
  subs = info['data'][0]['stats']['member_count']

  send_event('naked-data-subscribers', current: subs)
end
