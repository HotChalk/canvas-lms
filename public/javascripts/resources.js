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
    $("#resources").submit(function(event) {
      var $this = $(this);
      $(".resource_link .url").each(function() {
        $(this).removeAttr('name');
      }).filter(":not(.blank)").each(function() {
        var title = $.trim($(this).parents(".resource_link").find(".title").val().replace(/\[|\]/g, '_'));
        if(title) {
          $(this).attr('name', 'resources_links[' + title + ']');
        }
      });
    });
    $(".add_resource_link").click(function(event) {
      event.preventDefault();
      var $filter = $(".resource_link.blank:first").clone(true).removeClass('blank');
      $("#resources_links").append($filter.show());
    });
    $(".delete_resource_link").click(function(event) {
      event.preventDefault();
      $(this).parents(".resource_link").remove();
    });
    if($(".resource_link:not(.blank)").length == 0) {
      $(".add_resource_link").click();
    }
    $(".resources_help_link").click(function(event) {
      event.preventDefault();
      $("#resources_help_dialog").dialog({
        title: I18n.t('titles.resources', "Resources"),
        width: 400
      });
    });
    $("#enable_resources_link").change(function(event) {
      $("#resources_links_container").toggle();
    });
  });

});
