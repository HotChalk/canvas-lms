
define([
  'INST' /* INST */,
  'i18n!link_content_dialog',
  'jquery' /* $ */,
  'jquery.ajaxJSON' /* ajaxJSON */,
  'jquery.instructure_forms' /* ajaxJSONFiles, getFormData, errorBox */,
  'jqueryui/dialog',
  'compiled/jquery/fixDialogButtons' /* fix dialog formatting */,
  'jquery.instructure_misc_helpers' /* replaceTags, getUserServices, findLinkForService */,
  'jquery.instructure_misc_plugins' /* showIf */,
  'jquery.keycodes' /* keycodes */,
  'jquery.loadingImg' /* loadingImage */,
  'jquery.templateData' /* fillTemplateData */
], function(INST, I18n, $) {

$(document).ready(function() {
  var $dialog = $("#select_context_content_dialog");
  INST = INST || {};
  INST.linkContentDialog = function(options) {
    var select_button_text = options.select_button_text || I18n.t('buttons.add_link', "Add Link");
    var dialog_title = options.dialog_title || I18n.t('titles.add_link', "Add Link");
    $dialog.data('submitted_function', options.submit);
    $dialog.find(".add_item_button").text(select_button_text);
    $('#add_module_item_select').change();
    $("#select_context_content_dialog .module_item_select").change();
    $("#select_context_content_dialog").dialog({
      title: dialog_title,
      width: 400
    }).fixDialogButtons();
    $("#select_context_content_dialog").dialog('option', 'title', dialog_title);
  };
  $("#select_context_content_dialog .cancel_button").click(function() {
    $dialog.find('.alert').remove();
    $dialog.dialog('close');
  });
  $("#select_context_content_dialog .add_item_button").click(function() {
    var submit = function(item_data) {
      $dialog.dialog('close');
      $dialog.find('.alert').remove();
      var submitted = $dialog.data('submitted_function');
      if(submitted && $.isFunction(submitted)) {
        submitted(item_data);
      }
    };
    var item_type = $("#add_module_item_select").val();
    var $options = $("#select_context_content_dialog .module_item_option:visible:first .module_item_select option:selected");
    $options.each(function() {
      var $option = $(this);
      var item_data = {
        'item[type]': item_type,
        'item[id]': $option.val(),
        'item[title]': $option.text()
      };
      submit(item_data);
    });
  });
  $("#add_module_item_select").change(function() {
    $("#select_context_content_dialog .module_item_option").hide();
    $("#" + $(this).val() + "s_select").show().find(".module_item_select").change();
  });
  $("#select_context_content_dialog .module_item_select").change(function() {
    if($(this).val() == "new") {
      $(this).parents(".module_item_option").find(".new").show().focus().select();
    } else {
      $(this).parents(".module_item_option").find(".new").hide();
    }
  })
});
});
