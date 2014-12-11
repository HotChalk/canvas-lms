require 'lib/canvas/require_js/plugin_extension'
module Canvas
  module RequireJs
    class << self
      @@matcher = nil
      def get_binding
        binding
      end

      PATH_REGEX = %r{.*?/javascripts/(plugins/)?(.*)\.js\z}
      JS_ROOT = "#{Rails.root}/public/javascripts"

      def matcher=(value)
        @@matcher = value
      end

      def matcher
        @@matcher || ENV['JS_SPEC_MATCHER'] || '**/*Spec.js'
      end

      # get all regular canvas (and plugin) bundles
      def app_bundles
        app_bundles = (
          Dir["#{JS_ROOT}/compiled/bundles/*.js"] +
          Dir["#{JS_ROOT}/plugins/*/compiled/bundles/*.js"]
        ).inject({}) { |hash, file|
            # plugins have their name prepended, since that's we do the paths
            name = file.sub(PATH_REGEX, '\2')
            unless name == 'compiled/bundles/common'
              hash[name] = { :name => name, :exclude => ['common', 'ckeditor-all'] }
            end
            hash
          }
    
        # inject any bundle extensions defined in plugins
        extensions_for("*").each do |bundle, extensions|
          if app_bundles["compiled/bundles/#{bundle}"]
            app_bundles["compiled/bundles/#{bundle}"][:include] = extensions
          else
            $stderr.puts "WARNING: can't extend #{bundle}, it doesn't exist"
          end
        end

        app_bundles.values.sort_by{ |b| b[:name] }.to_json[1...-1].gsub(/,\{/, ",\n    {")
      end

      # get extensions for a particular bundle (or all, if "*")
      def extensions_for(bundle, plugin_path = '')
        result = {}
        Dir["#{JS_ROOT}/plugins/*/compiled/bundles/extensions/#{bundle}.js"].each do |file|
          name = file.sub(PATH_REGEX, '\2')
          b = name.sub(%r{.*/}, '')
          result[b] ||= []
          result[b] << plugin_path + name
        end
        bundle == '*' ? result : (result[bundle.to_s] || [])
      end

      def paths(cache_busting = false)
        @paths ||= {
          :common => 'compiled/bundles/common',
          :jqueryui => 'vendor/jqueryui',
          :uploadify => '../flash/uploadify/jquery.uploadify-3.1',
          'ic-dialog' => 'vendor/ic-dialog/dist/main.amd',
          'swfobject' => 'vendor/swfobject/swfobject',
          'swfupload' => 'vendor/swfupload/swfupload',
          'ckeditor-core' => 'ckeditor/ckeditor',
          'ckeditor-jquery' => 'ckeditor/adapters/jquery'
        }.update(cache_busting ? cache_busting_paths : {}).update(plugin_paths).update(Canvas::RequireJs::PluginExtension.paths).to_json.gsub(/([,{])/, "\\1\n    ")
      end

      def packages
        @packages ||= [
          {'name' => 'ic-data', 'location' => 'bower/ic-data/dist/amd'},
          {'name' => 'ic-ajax', 'location' => 'bower/ic-ajax/dist/amd'},
          {'name' => 'ic-styled', 'location' => 'bower/ic-styled'},
          {'name' => 'ic-menu', 'location' => 'bower/ic-menu'},
          {'name' => 'ic-tabs', 'location' => 'bower/ic-tabs/dist/amd'},
          {'name' => 'ic-lazy-list', 'location' => 'bower/ic-lazy-list/dist/amd'},
          {'name' => 'ic-modal', 'location' => 'bower/ic-modal/dist/amd'},
          {'name' => 'ember-qunit', 'location' => 'bower/ember-qunit/dist/amd'},
        ].to_json
      end

      def plugin_paths
        @plugin_paths ||= begin
          Dir['public/javascripts/plugins/*'].inject({}) { |hash, plugin|
            plugin = plugin.sub(%r{public/javascripts/plugins/}, '')
            hash[plugin] = "plugins/#{plugin}"
            hash
          }
        end
      end

      def cache_busting_paths
        {}
      end
      
      def shims
        <<-JS.gsub(%r{\A +|^ {8}}, '')
          {
            'bower/ember/ember': {
              deps: ['jquery', 'handlebars'],
              exports: 'Ember'
            },
            'bower/ember-data/ember-data': {
              deps: ['ember'],
              exports: 'DS'
            },
            'bower/handlebars/handlebars.runtime': {
              exports: 'Handlebars'
            },
            'vendor/FileAPI/FileAPI.min': {
              deps: ['jquery', 'vendor/FileAPI/config'],
              exports: 'FileAPI'
            },
            'uploadify': {
              deps: ['jquery', 'swfobject', 'swfupload'],
              exports: '$'
            },
            'vendor/bootstrap-select/bootstrap-select' : {
              deps: ['jquery'],
              exports: '$'
            },
            'vendor/jquery.jcrop': {
              deps: ['jquery'],
              exports: '$'
            },
            'handlebars': {
              deps: ['bower/handlebars/handlebars.runtime.amd'],
              exports: 'Handlebars'
            },
            'ckeditor-jquery': {
              deps:['jquery', 'ckeditor-core']
            }
          }
        JS
      end
    end
  end
end
