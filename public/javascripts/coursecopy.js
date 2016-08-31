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
    $('#input_file').html("No file chosen");      
    $( "#coursecopytoolFileUpload" ).change(function() {
      var csvFile = $("#coursecopytoolFileUpload").val();
      if (csvFile)
      {
        var arrname = csvFile.split("\\");
        if (arrname.length > 0)
        {
          $('#input_file').html(arrname[arrname.length - 1]);        
        }
      }
      else{
        $('#input_file').html("No file chosen");      
      }      
    });
  });

});
