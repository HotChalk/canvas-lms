define([
  'INST' /* INST */,
  'i18n!link_content_dialog',
  'jquery' /* $ */,
  'react',
  'jsx/context_modules/FileSelectBox',
  'jquery.instructure_date_and_time' /* datetime_field */,
  'jquery.ajaxJSON' /* ajaxJSON */,
  'jquery.instructure_forms' /* ajaxJSONFiles, getFormData, errorBox */,
  'jqueryui/dialog',
  'compiled/jquery/fixDialogButtons' /* fix dialog formatting */,
  'jquery.instructure_misc_helpers' /* replaceTags, getUserServices, findLinkForService */,
  'jquery.instructure_misc_plugins' /* showIf */,
  'jquery.keycodes' /* keycodes */,
  'jquery.loadingImg' /* loadingImage */,
  'jquery.templateData' /* fillTemplateData */
], function(INST, I18n, $, React, FileSelectBox) {

$(document).ready(function() {
  var $dialog = $("#link_context_content_dialog");
  INST = INST || {};
  INST.linkContentDialog = function(options) {
    var select_button_text = options.select_button_text || I18n.t('buttons.add_link', "Add Link");
    var dialog_title = options.dialog_title || I18n.t('titles.add_link', "Add Link");
    $dialog.data('submitted_function', options.submit);
    $dialog.find(".add_item_button").text(select_button_text);
    $('#add_module_item_select').change();
    $("#link_context_content_dialog .module_item_select").change();
    $("#link_context_content_dialog").dialog({
      title: dialog_title,
      width: 400
    }).fixDialogButtons();
    $("#link_context_content_dialog").dialog('option', 'title', dialog_title);
  };
  $("#link_context_content_dialog .cancel_button").click(function() {
    $dialog.find('.alert').remove();
    $dialog.dialog('close');
  });
  $("#link_context_content_dialog .add_item_button").click(function() {
    var submit = function(item_data) {
      $dialog.dialog('close');
      $dialog.find('.alert').remove();
      var submitted = $dialog.data('submitted_function');
      if(submitted && $.isFunction(submitted)) {
        submitted(item_data);
      }
    };
    var item_type = $("#add_module_item_select").val();
    if (item_type === 'external_url')
    {
      function validate_url(url){
        var urlR = '^(?!mailto:)(?:(?:http|https|ftp)://)(?:\\S+(?::\\S*)?@)?(?:(?:(?:[1-9]\\d?|1\\d\\d|2[01]\\d|22[0-3])(?:\\.(?:1?\\d{1,2}|2[0-4]\\d|25[0-5])){2}(?:\\.(?:[0-9]\\d?|1\\d\\d|2[0-4]\\d|25[0-4]))|(?:(?:[a-z\\u00a1-\\uffff0-9]+-?)*[a-z\\u00a1-\\uffff0-9]+)(?:\\.(?:[a-z\\u00a1-\\uffff0-9]+-?)*[a-z\\u00a1-\\uffff0-9]+)*(?:\\.(?:[a-z\\u00a1-\\uffff]{2,})))|localhost)(?::\\d{2,5})?(?:(/|\\?|#)[^\\s]*)?$';
        var result = url.match(urlR);
        if (result === null || result.lenght == 0){return false;}
        else{return true;}  
      };
      var external_url = $('#url_address').val();           
      if (validate_url(external_url)){
        var external_url_title = $('#url_title').val();
        var item_data = {
          'item[type]': item_type,
          'item[id]': btoa(external_url),
          'item[title]': external_url_title
        };
        submit(item_data);
      }
      else{        
        $.flashError(I18n.t('errors.wrong_url', "The provided URL is not correct. Please enter another address."));
      }            
    }
    else
    {
      var $options = $("#link_context_content_dialog .module_item_option:visible:first .module_item_select option:selected");
      $options.each(function() {
        var $option = $(this);
        var item_data = {
          'item[type]': item_type,
          'item[id]': $option.val(),
          'item[title]': $option.text()
        };
        submit(item_data);
      });  
    }
  
  });
  $("#add_module_item_select").change(function() {
    $("#link_context_content_dialog .module_item_option").hide();
    if ($(this).val() === 'attachment') {
      React.render(React.createFactory(FileSelectBox)({contextString: ENV.context_asset_string, allowNewFile: false}), $('#module_item_select_file')[0]);
    }
    $("#" + $(this).val() + "s_select").show().find(".module_item_select").change();
  });
  $("#link_context_content_dialog .module_item_select").change(function() {
    if($(this).val() == "new") {
      $(this).parents(".module_item_option").find(".new").show().focus().select();
    } else {
      $(this).parents(".module_item_option").find(".new").hide();
    }
  })
});
});
