require 'optparse'

namespace :canvas do
  namespace :domain do
    desc 'List or replace all references to a domain name in the database.'
    task :query => :environment do
      option_parser = OptionParser.new
      option_parser.banner = "Usage: rake canvas:domains:query [options]"
      option_parser.on("-s", "--search-domain {domain name}", "Search domain name") do |search_domain|
        @search_domain = search_domain
      end
      option_parser.on("-r", "--replace-domain {domain name}", "Replace domain name") do |replace_domain|
        @replace_domain = replace_domain
      end
      option_parser.on("-p", "--replace-protocol {protocol}", "Replace protocol") do |replace_protocol|
        @replace_protocol = replace_protocol
      end
      option_parser.on("-d", "--[no-]debug", "Show debug info in output log") do |debug|
        @debug = debug
      end
      args = option_parser.order!(ARGV) {}
      option_parser.parse!(args)
      validator = DomainValidator.new(@search_domain, @replace_domain,
                                     @replace_protocol,@debug)
      validator.check_all
    end
  end
end
