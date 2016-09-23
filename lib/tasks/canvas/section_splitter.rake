require 'optparse'

namespace :canvas do
  namespace :section_splitter do
    desc 'Split multi-section course(s) into separate course shells'
    task :split => :environment do
      options = {}
      option_parser = OptionParser.new
      option_parser.banner = "Usage: rake canvas:section_splitter:split [options]"
      option_parser.on("-u", "--user {user ID}", "User ID (needs admin privileges)", Integer) do |user_id|
        options[:user_id] = user_id
      end
      option_parser.on("-c", "--course {course ID}", "Single course ID", Integer) do |course_id|
        options[:course_id] = course_id
      end
      option_parser.on("-a", "--account {account ID}", "Account or subaccount ID", Integer) do |account_id|
        options[:account_id] = account_id
      end
      option_parser.on("-d", "--[no-]delete", "Delete course after splitting") do |delete|
        options[:delete] = delete
      end
      args = option_parser.order!(ARGV) {}
      option_parser.parse!(args)
      Canvas::SectionSplitter.run(options)
    end
  end
end