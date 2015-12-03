define [
  'jquery'
  'underscore'
  'Backbone'
  'i18n!calendar.edit'
  'jst/DiscussionTopics/replyAssignmentRemovedDialog'
  'str/htmlEscape'
  'jqueryui/dialog'
  'compiled/jquery/fixDialogButtons'
], ($, _, {View}, I18n, template, htmlEscape) ->

  class ReplyAssignmentRemovedDialogView extends View
    dialogTitle: """
      <span>
        <i class="icon-warning"></i>
        #{htmlEscape I18n.t('titles.warning', 'Warning')}
      </span>
    """

    initialize: (options) ->
      super
      @success      = options.success


    render: ->
      @showDialog()
      this

    showDialog: ->
      tpl = template()
      @$dialog = $(tpl).dialog
        dialogClass: 'dialog-warning'
        draggable  : false
        modal      : true
        resizable  : false
        title      : $(@dialogTitle)
      .fixDialogButtons()
      .on('click', '.btn', @onAction)
      @$dialog.parents('.ui-dialog:first').focus()

    onAction: (e) =>
      if $(e.currentTarget).hasClass('btn-primary')
        @success(@$dialog)
      else
        @cancel()

    cancel: (e) =>
      @$dialog.dialog('close').remove()
