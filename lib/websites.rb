require 'hashie'

$config = File.open("websites.json") { |f| Hashie::Mash.new(JSON.load(f)) }

# process config file
for property in $config.websites + $config.apis
  # default id from title
  property.id = property.title.downcase.gsub(/[ .]/, '-') if property.id.nil?
end

def get_websites
  $config.websites
end

def get_apis
  $config.apis
end
