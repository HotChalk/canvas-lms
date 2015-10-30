define [
  'Backbone'
  'underscore'
  'i18n!overrides'
  'compiled/models/AssignmentOverride'
  'compiled/models/Section'
], ({Model}, _, I18n, AssignmentOverride, Section) ->

  class DueDateList

    constructor: (@overrides, @sections, @assignment) ->
      @courseSectionsLength = @sections.length
      @sections.add Section.defaultDueDateSection() unless ENV.LIMIT_PRIVILEGES_TO_COURSE_SECTION

      @_addOverrideForDefaultSectionIfNeeded()

    getDefaultDueDate: =>
      @overrides.getDefaultDueDate()

    overridesContainDefault: =>
      @overrides.containsDefaultDueDate()

    containsSectionsWithoutOverrides: =>
      return false if @overrides.containsDefaultDueDate()
      @sectionsWithOverrides().length < @courseSectionsLength

    sectionsWithOverrides: =>
      @sections.select (section) =>
        section.id in @_overrideSectionIDs() &&
          section.id isnt @defaultDueDateSectionId

    sectionsWithoutOverrides: =>
      @sections.select (section) =>
        section.id not in @_overrideSectionIDs() &&
          section.id isnt @defaultDueDateSectionId

    defaultDueDateSectionId: Section.defaultDueDateSectionID

    showDueDate: true

    # --- private helpers ---

    _overrideSectionIDs: => @overrides.courseSectionIDs()

    _onlyVisibleToOverrides: =>
      ENV.DIFFERENTIATED_ASSIGNMENTS_ENABLED && @assignment.isOnlyVisibleToOverrides()

    _addOverrideForDefaultSectionIfNeeded: =>
      return if @_onlyVisibleToOverrides()
      override = AssignmentOverride.defaultDueDate
        due_at: @assignment.get('due_at')
        lock_at: @assignment.get('lock_at')
        unlock_at: @assignment.get('unlock_at')
      if ENV.LIMIT_PRIVILEGES_TO_COURSE_SECTION && ENV.SECTION_LIST && ENV.SECTION_LIST.length
        if ENV.SECTION_LIST.length == 1
          default_section_id = ENV.SECTION_LIST[0].id
        else
          return

        override.set 'course_section_id', default_section_id
      @overrides.add override
