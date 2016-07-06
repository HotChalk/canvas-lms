namespace :canvas do
  namespace :section_splitter do
    desc 'Split multi-section course(s) into separate course shells'
    task :split => :environment do |t, args|
      Canvas::SectionSplitter.perform(args)
    end
  end
end
