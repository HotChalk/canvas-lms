require 'i18n_tasks'
require 'i18n_extraction'

namespace :ember do
  SEARCH_REGEXES = {
    /Instructure Canvas/ => "HotChalk Ember",
    /Canvas(?! ((Guides)|(by Instructure)|(Cartridge)|(Common Cartridge)|(Ticketing)|(Course Export)|(Cloud)|(Attribute)|(Network)|(Translation)|(\.net)|(Open API)|(Community)))/ => "HotChalk Ember"
  }

  desc "Generates a new override file for Ember branding"
  task :generate_i18n_overrides do
    require 'ya2yaml'
    Hash.send(:include, I18nTasks::HashExtensions) unless Hash.new.kind_of?(I18nTasks::HashExtensions)

    input_dir = './config/locales/generated'
    output_dir = './config/locales/overrides'
    FileUtils.mkdir_p(output_dir)
    Dir.glob(File.join(input_dir, '*.yml')).each do |input_file|
      output_file = File.join(output_dir, File.basename(input_file))
      input_keys = YAML.safe_load(File.read(input_file)).flatten_keys
      output_keys = rebrand(input_keys)
      File.open(output_file, "w") do |file|
        file.write(output_keys.expand_keys.ya2yaml(:syck_compatible => true))
      end
      print "Wrote new #{output_file}\n\n"
    end
  end

  # Identifies the values in the supplied hash that contain Instructure Canvas branding and
  # returns a new hash that contains a HotChalk Ember-branded version.
  def rebrand(keys)
    result = {}
    keys.each_pair do |key, value|
      new_value = value
      case value
        when String
          SEARCH_REGEXES.each_pair {|regex, replace|
            new_value = new_value.gsub(regex, replace)
          }
      end
      result.merge!({key => new_value}) if value != new_value
    end
    result.sort_by{|k, v| k}.to_h
  end


  desc "Generates i18n overrides file for Ember branding in JS files"
  task :generate_i18n_overrides_js do
    Hash.send(:include, I18nTasks::HashExtensions) unless Hash.new.kind_of?(I18nTasks::HashExtensions)

    js_keys = JSON.parse(File.read("config/locales/generated/js_bundles.json")).flatten_keys.values.flatten

    input_dir = './config/locales/overrides'
    output_dir = './public/javascripts/translations'
    output_keys = {}
    unless ENV['GENERATE_I18N_OVERRIDES'] == '0'
      Dir.glob(File.join(input_dir, '*.yml')).each do |input_file|
        locale_name = File.basename(input_file, '.yml')
        all_keys = YAML.safe_load(File.read(input_file))[locale_name].flatten_keys
        output_keys.merge!({locale_name => all_keys.select {|k, v| js_keys.include?(k)}.expand_keys})
      end
    end
    output_file = File.join(output_dir, '_overrides.js')
    content = I18nTasks::Utils.dump_js(output_keys)
    File.open(output_file, "w") do |file|
      file.write(content)
    end
  end
end
