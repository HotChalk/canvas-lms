namespace :canvas do
  namespace :domain do
    desc 'List all references to a domain name in the database.'
    task :query, [ :domain ] => :environment do |t, args|
      domain_regex = /^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}$/
      domain = args[:domain]
      unless domain_regex.match domain
        puts "Invalid domain name!"
        return
      end
      DomainValidator.queue(domain)
    end
  end
end
