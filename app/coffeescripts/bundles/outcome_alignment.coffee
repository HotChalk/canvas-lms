require [
  'jquery'  
  'jqueryui/sortable'
  'jquery.ajaxJSON'
], ($) ->

  $("#alignments").sortable({
    handle: '.move_alignment_link',
    helper: 'clone',
    axis: 'y',
    tolerance: 'pointer',
    update: (e, ui) ->
      reorder_url = $('.reorder_alignments_url').attr('href')
      outcome_id = $('#alignments').data('id')
      alignment_ids = []

      $('.alignment').each ->
        alignment_id = $(this).data('id')
        if alignment_id != 'blank'
          alignment_ids.push(alignment_id)
            
      ordered_ids = alignment_ids.join(',')
      
      
      $.ajaxJSON reorder_url, 'POST', { 'outcome_id': outcome_id, 'order': ordered_ids}, ->
        $.flashMessage 'Alignment successfully deleted'
  })

  $('.delete_alignment_link').click (e) ->
    e.preventDefault()
    self = $(this)
    $.ajaxJSON self.attr('href'), 'DELETE', {}, ->
      self.parents('li.alignment').remove();
      $.flashMessage 'Alignment successfully deleted'    