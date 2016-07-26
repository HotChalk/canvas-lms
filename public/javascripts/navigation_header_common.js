define([
  'i18n!resources',
  'jquery', // $
  'jquery.ajaxJSON', // ajaxJSON
  'jquery.instructure_date_and_time', // date_field, time_field, datetime_field, /\$\.datetime/
  'jquery.instructure_forms', // formSubmit, getFormData, validateForm
  'jqueryui/dialog',
  'jquery.instructure_misc_helpers', // replaceTags
  'jquery.instructure_misc_plugins', // confirmDelete, showIf, /\.log/
  'jquery.loadingImg' // loadingImg, loadingImage
], function(I18n, $) {

  $(document).ready(function() {
    $("#help_link").click(function(event) {
      event.preventDefault();
      $("#help_container").dialog({
        title: I18n.t('popup.help', "Help"),
        width: 400,
        open: function(event, ui) { $('.ui-dialog-titlebar-close').focus(); }
      });
    });
  });

});
