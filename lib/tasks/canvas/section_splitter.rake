require 'optparse'

namespace :canvas do
  namespace :section_splitter do
    desc 'Split multi-section course(s) into separate course shells'
    task :split => :environment do |t, args|
      options = {}
      OptionParser.new(args) do |opts|
        opts.banner = "Usage: rake canvas:section_splitter:split [options]"
        opts.on("-c", "--course {course ID}", "Single course ID", Integer) do |course_id|
          options[:course_id] = course_id
        end
        opts.on("-a", "--account {account ID}", "Account or subaccount ID", Integer) do |account_id|
          options[:account_id] = account_id
        end
      end.parse!
      Canvas::SectionSplitter.run(options)
    end
  end
end
