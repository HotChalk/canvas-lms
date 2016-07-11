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
    
    $("#help_setup").submit(function(event) {
      var $this = $(this);
    });
    $(".edit_help_setup_link").click(function(event) {
      event.preventDefault();
      var help_option = JSON.parse($(this).attr('id'));  
      editHelpOption(help_option);
    });
    var editHelpOption = function(help_option){
      $("#title").val(help_option.title);
      $("#url").val(help_option.url);
      setHiddenInput(help_option.url);      
      $("#description").val(help_option.description);
      $("#x_id").val(help_option.x_id);
      $("#x_classes").val(help_option.x_classes);
      $("#javascript_txt").val(help_option.javascript_txt);
      
      $("#help_setup_container").dialog({
        title: I18n.t('titles.help', "Help Setup"),
        width: 600
      });
    }; 
    var setHiddenInput = function(val)
    {
      var url_old = $("#url_old");

      if (url_old.length == 0)
      {
        $('<input>').attr({
          id : 'url_old', 
          name : 'url_old', 
          type : 'hidden',
          value : val
        }).appendTo('.help_setup_link');
      }
      else {url_old.val(val);}
    };
    $(".delete_help_setup_link").click(function(event) {
      event.preventDefault();
      var help_option = JSON.parse($(this).attr('id'));  
      
      $.ajaxJSON(ENV.url, 'DELETE', {url:help_option.url}, function(data) {
        location.reload();
        $.screenReaderFlashMessage(I18n.t('Help Link was deleted'));
      }, $.noop);

    });
    $(".add_help_setup_link").click(function(event) {
      event.preventDefault();
      var url_old = $("#url_old");
      if (url_old.length > 0)
      {
        $( "#url_old" ).remove();
        $("#title").val("");
        $("#url").val("");
        $("#description").val("");
        $("#x_id").val("");
        $("#x_classes").val("");
        $("#javascript_txt").val("");
      }

      $("#help_setup_container").dialog({
        title: I18n.t('titles.help', "Help Setup"),
        width: 600
      });
    });    
  });

});
