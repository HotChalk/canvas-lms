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
      option_parser.on("-P", "--[no-]postgres", "Delete data in Postgres RDBMS") do |postgres|
        options[:postgres] = postgres
      end
      option_parser.on("-C", "--[no-]cassandra", "Delete data in Cassandra") do |cassandra|
        options[:cassandra] = cassandra
      end
      option_parser.on("-E", "--explain", "Show EXPLAIN plans for expensive Postgres queries") do |explain|
        options[:explain] = explain
      end
      option_parser.on("-M", "--truncate-messages", "Copy and truncate the messages table (recommended for large accounts)") do |truncate_messages|
        options[:truncate_messages] = truncate_messages
      end
      args = option_parser.order!(ARGV) {}
      option_parser.parse!(args)
      tool = AccountRemover.new(options)
      tool.run
    end
  end
end
