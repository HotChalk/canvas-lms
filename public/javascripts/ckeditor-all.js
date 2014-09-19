define([
  'ckeditor-jquery',

  // Add all required modules for plugins here. CKEditor doesn't use RequireJS to load dependencies, so we
  // are forced to load them synchronously in each plugin file. However, they must already have been loaded for
  // that to work!
  'i18n!editor',
  'jquery',
  'str/htmlEscape',
  'jqueryui/dialog',
  'vendor/scribd.view',
  'jquery.instructure_misc_helpers',
  'jquery.instructure_misc_plugins',
  'jquery.dropdownList'
], function () {

  // Get CKEditor plugin load path
  var parser = document.createElement('a');
  parser.href = CKEDITOR.basePath;
  var loadPath = parser.pathname.replace('ckeditor', 'ckeditor-plugins');

  // Add all plugins here
  CKEDITOR.plugins.addExternal('instructure_links', loadPath + 'instructure_links/', 'plugin.js');
  CKEDITOR.plugins.addExternal('instructure_image', loadPath + 'instructure_image/', 'plugin.js');
  CKEDITOR.plugins.addExternal('instructure_external_tools', loadPath + 'instructure_external_tools/', 'plugin.js');

});
