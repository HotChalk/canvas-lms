define([
  'jsx/course_copy/ContentMigrationList',
  'i18n!resources',
  'jquery', // $
  'jquery.ajaxJSON', // ajaxJSON
  'jquery.instructure_date_and_time', // date_field, time_field, datetime_field, /\$\.datetime/
  'jquery.instructure_forms', // formSubmit, getFormData, validateForm
  'jqueryui/dialog',
  'jquery.instructure_misc_helpers', // replaceTags
  'jquery.instructure_misc_plugins', // confirmDelete, showIf, /\.log/
  'jquery.loadingImg' // loadingImg, loadingImage  
], function(ContentMigrationList, I18n, $ ) {

  $(document).ready(function() {    
    if (ENV.content_migrations && ENV.content_migrations.length > 0){
      var obj_container = document.getElementById('progress_result');
      var contentMigrationList = React.createFactory(ContentMigrationList);
      React.render( contentMigrationList({migrations:ENV.content_migrations, showCollapsed:true}), obj_container);
    }
  });
  
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
  $(document).ready(function () {
      // $('.panel-heading span.clickable').click();
      // $('.panel div.clickable').click();
  });

  
});
