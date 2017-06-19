require 'optparse'

namespace :canvas do
  namespace :content do
    desc 'Find strings in course content.'
    task :query => :environment do
      option_parser = OptionParser.new
      option_parser.banner = "Usage: rake canvas:content:query [options]"
      option_parser.on("-s", "--search-text {text}", "Search for text") do |search_text|
        @search_text = search_text
      end
      option_parser.on("-a", "--account-ids {account ids}", "Account IDs") do |account_ids|
        @account_ids = account_ids.split(',')
      end
      args = option_parser.order!(ARGV) {}
      option_parser.parse!(args)
      search = ContentSearch.new(@search_text, @account_ids)
      search.search_all
    end
  end
end
