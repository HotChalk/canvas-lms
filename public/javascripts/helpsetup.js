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
      if($("#title").val().trim() == "") {
        event.preventDefault();
        event.stopPropagation();
        return $("#title").formErrors({
          help_title: I18n.t('errors.help_title', "Please add a title.")
        });
      }
      if($("#url").val().trim() == "") {
        if($("#javascript_txt").val().trim() == "") {
          event.preventDefault();
          event.stopPropagation();
          return $("#url").formErrors({
            help_url: I18n.t('errors.help_url', "Please add a valid link.")
          });
        }
      }
      else{
        if (!validate_url($("#url").val()))
        {
            event.preventDefault();
            event.stopPropagation();
            return $("#url").formErrors({
              help_url: I18n.t('errors.help_url', "Please add a valid link.")
            });   
        }
      }
      if($("#description").val().trim() == "") {
        event.preventDefault();
        event.stopPropagation();
        return $("#description").formErrors({
          help_description: I18n.t('errors.help_description', "Please add a description.")
        });
      }
    });

    $(".edit_help_setup_link").click(function(event) {
      event.preventDefault();
      var help_option = JSON.parse($(this).attr('id'));  
      editHelpOption(help_option);
    });

    var validate_url = function(url) {
      return /^(http|https)?:\/\/[a-zA-Z0-9-\.]+\.[a-z]{2,4}/.test(url);      
    };

    var editHelpOption = function(help_option){
      $("#title").val(help_option.title);
      setHiddenInput(help_option.title);      
      $("#url").val(help_option.url);
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
      var title_old = $("#title_old");

      if (title_old.length == 0)
      {
        $('<input>').attr({
          id : 'title_old', 
          name : 'title_old', 
          type : 'hidden',
          value : val
        }).appendTo('.help_setup_link');
      }
      else {title_old.val(val);}
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
      var title_old = $("#title_old");
      if (title_old.length > 0)
      {
        $( "#title_old" ).remove();
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
