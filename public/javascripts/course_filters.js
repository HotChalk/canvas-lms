define([
  'i18n!courses',
  'jquery' /* $ */
], function(I18n, $) {
  $(document).ready(function() {
    $(".course-toggle").click(function(event) {
      event.preventDefault();
      var $course_radio = $('#course_date_in');
      if($course_radio.is(':checked')){
        return;
      }

      var $section_radio = $('#section_date_in'),
          $course_label = $(this),
          $section_label = $('.section-toggle');
      
      $course_radio.prop('checked', true);
      $section_radio.prop('checked', false);
      $course_label.addClass('ui-state-active');
      $section_label.removeClass('ui-state-active');
    });

    $(".section-toggle").click(function(event) {
      event.preventDefault();
      var $section_radio = $('#section_date_in');
      if($section_radio.is(':checked')){
        return;
      }

      var $course_radio = $('#course_date_in'),
          $course_label = $('.course-toggle'),
          $section_label = $(this);
      
      $course_radio.prop('checked', false);
      $section_radio.prop('checked', true);
      $section_label.addClass('ui-state-active');
      $course_label.removeClass('ui-state-active');
    });
  });
});

