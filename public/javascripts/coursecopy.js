define([
  'jsx/course_copy/ContentMigrationList',
  'jsx/due_dates/DueDateCalendars',
  'i18n!resources',
  'jquery', // $
  'jquery.ajaxJSON', // ajaxJSON
  'jquery.instructure_date_and_time', // date_field, time_field, datetime_field, /\$\.datetime/
  'jquery.instructure_forms', // formSubmit, getFormData, validateForm
  'jqueryui/dialog',
  'jquery.instructure_misc_helpers', // replaceTags
  'jquery.instructure_misc_plugins', // confirmDelete, showIf, /\.log/
  'jquery.loadingImg' // loadingImg, loadingImage  
], function(ContentMigrationList, DueDateCalendars, I18n, $ ) {
  
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
    getProgress();      
  });

  showProgress = function(){
    if (ENV.content_migrations && ENV.content_migrations.length > 0){
      var obj_container = document.getElementById('progress_result');
      var contentMigrationList = React.createFactory(ContentMigrationList);
      React.render( contentMigrationList({migrations:ENV.content_migrations, showCollapsed:false}), obj_container);
    }
  };

  getProgress = function(){
    $.ajax({
      url: ENV.progress_url,
      type: "GET",
      data: {},
      success: function(data) {
        ENV.content_migrations = data;
        showProgress();
      },
      error: function() {
        console.log('error on ajax call...');
      }
    });    
  };
  
  var local_timer = setInterval(getProgress, 15000);  
  setTimeout(getProgress, 15000);

  $(document).on('click', '.panel-heading span.clickable', function (e) {
      var $this = $(this);
      if (!$this.hasClass('panel-collapsed')) {
          $this.parents('.panel').find('.panel-body').slideUp();
          $this.addClass('panel-collapsed');
          $this.find('i').removeClass('icon-minimize').addClass('icon-plus');
      } else {
          $this.parents('.panel').find('.panel-body').slideDown();
          $this.removeClass('panel-collapsed');
          $this.find('i').removeClass('icon-plus').addClass('icon-minimize');
      }
  });
  $(document).on('click', '.panel div.clickable', function (e) {
      var $this = $(this);
      if (!$this.hasClass('panel-collapsed')) {
          $this.parents('.panel').find('.panel-body').slideUp();
          $this.addClass('panel-collapsed');
          $this.find('i').removeClass('icon-minimize').addClass('icon-plus');
      } else {
          $this.parents('.panel').find('.panel-body').slideDown();
          $this.removeClass('panel-collapsed');
          $this.find('i').removeClass('icon-plus').addClass('icon-minimize');
      }
  });
});
