define [
  'i18n!assignment'
  'Backbone'
  'underscore'
  'jquery'
  'compiled/views/assignments/AssignmentGroupCreateDialog'
  'jst/assignments/AssignmentGroupSelector'
], (I18n, Backbone, _, $, AssignmentGroupCreateDialog, template) ->

  class AssignmentGroupSelector extends Backbone.View

    template: template

    ASSIGNMENT_GROUP_ID = '#assignment_group_id'

    els: do ->
      {}

    events: do ->
      {}

    @optionProperty 'parentModel'
    @optionProperty 'assignmentGroups'
    @optionProperty 'nested'
    @optionProperty 'basePrefix'

    initialize: (options) ->
      assignmentGroupId = "##{options.basePrefix}_group_id"
      @els[assignmentGroupId] = '$assignmentGroupId'
      @events["change #{assignmentGroupId}"] = 'showAssignmentGroupCreateDialog'
      @fieldSelectors.assignmentGroupSelector = assignmentGroupId
      super

    showAssignmentGroupCreateDialog: =>
      if @$assignmentGroupId.val() is 'new'
        @dialog = new AssignmentGroupCreateDialog().render()
        @dialog.on 'assignmentGroup:created', (group) =>
          $newGroup = $('<option>')
          $newGroup.val(group.id)
          $newGroup.text(group.name)
          @$assignmentGroupId.prepend $newGroup
          @$assignmentGroupId.val(group.id)
        @dialog.on 'assignmentGroup:canceled', =>
          if @assignmentGroups[0]
            @$assignmentGroupId.val(@assignmentGroups[0].id)
          else
            @$assignmentGroupId.val("none")

    toJSON: =>
      assignmentGroups: @assignmentGroups
      assignmentGroupId: @parentModel.assignmentGroupId()
      frozenAttributes: @parentModel.frozenAttributes()
      nested: @nested
      basePrefix: @basePrefix || 'assignment'

    fieldSelectors:
      assignmentGroupSelector: '#assignment_group_id'

    validateBeforeSave: (data, errors) =>
      errors = @_validateAssignmentGroupId data, errors
      errors

    _validateAssignmentGroupId: (data, errors) =>
      agid = if @nested
        data.assignment.assignmentGroupId()
      else
        data.assignment_group_id

      if agid == 'new' or agid == 'none'
        errors["assignmentGroupSelector"] = [
          message: I18n.t 'assignment_group_must_have_group', 'Please select an assignment group for this assignment'
        ]
      errors
