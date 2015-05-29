define [
  'i18n!rubrics'
  'jquery'
  'str/htmlEscape'
  'jqueryui/dialog'
  'vendor/jquery.ba-tinypubsub'
], (I18n, $, htmlEscape) ->

  assignmentRubricDialog =

    # the markup for the trigger should look like:
    # <a class="rubric_dialog_trigger" href="#" data-rubric-exists="<%= !!attached_rubric %>" data-url="<%= context_url(@topic.assignment.context, :context_assignment_rubric_url, @topic.assignment.id) %>">
    #   <%= attached_rubric ? t(:show_rubric, "Show Rubric") : t(:add_rubric, "Add Rubric") %>
    # </a>

    initTriggers: ->
      if $triggers = $('.rubric_dialog_trigger')
        $triggers.each (i, el) ->
          noRubricExists = $(el).data('noRubricExists')
          url = $(el).data('url')
          $focusReturnsTo = $ $(el).data('focusReturnsTo')
    
          $(el).click (event) ->
            event.preventDefault()
            assignmentRubricDialog.openDialog(url, noRubricExists, $focusReturnsTo)

    initDialog: (url, noRubricExists, $focusReturnsTo) ->
      @dialogUrl = url
      @$dialog.dialog('destroy').remove() if @$dialog
      @$dialog = $("<div><h4>#{htmlEscape I18n.t 'loading', 'Loading...'}</h4></div>").dialog
        title: I18n.t("titles.assignment_rubric_details", "Assignment Rubric Details")
        width: 600
        modal: false
        resizable: true
        autoOpen: false
        close: => $focusReturnsTo.focus()

      $.get url, (html) ->
        # weird hackery because the server returns a <div id="rubrics" style="display:none">
        # as it's root node, so we need to show it before we inject it
        assignmentRubricDialog.$dialog.html $(html).show()

        # if there is not already a rubric, we want to click the "add rubric" button for them,
        # since that is the point of why they clicked the link.
        if noRubricExists
          $.subscribe 'edit_rubric/initted', ->
            assignmentRubricDialog.$dialog.find('.btn.add_rubric_link').click()

    openDialog: (url, noRubricExists, $focusReturnsTo) ->
      @initDialog(url, noRubricExists, $focusReturnsTo) unless @dialogUrl == url
      @$dialog.dialog 'open'

