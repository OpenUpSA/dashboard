require 'hashie'

def get_websites
  websites = File.open("websites.json") { |f| Hashie::Mash.new(JSON.load(f)) }.websites

  for website in websites
    # default id from title
    website.id = website.title.downcase.gsub(/[ .]/, '-') if website.id.nil?
  end

  websites
end
