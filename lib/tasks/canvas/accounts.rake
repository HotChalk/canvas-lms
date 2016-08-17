require 'optparse'

namespace :canvas do
  namespace :accounts do
    desc 'Completely remove a root account'
    task :remove => :environment do
      options = {}
      option_parser = OptionParser.new
      option_parser.banner = "Usage: rake canvas:accounts:remove [options]"
      option_parser.on("-a", "--account {account ID}", "Root account ID", Integer) do |account_id|
        options[:account_id] = account_id
      end
      args = option_parser.order!(ARGV) {}
      option_parser.parse!(args)
      tool = AccountRemover.new(options)
      tool.run
    end
  end
end
