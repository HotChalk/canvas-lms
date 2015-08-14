define [
  'i18n!groups'
  'Backbone'
  'underscore'
  'compiled/views/groups/manage/GroupCategoryDetailView'
  'compiled/views/groups/manage/GroupsView'
  'compiled/views/groups/manage/UnassignedUsersView'
  'compiled/views/groups/manage/AddUnassignedMenu'
  'jst/groups/manage/groupCategory'
  'compiled/jquery.rails_flash_notifications'
  'jquery.disableWhileLoading'
], (I18n, {View}, _, GroupCategoryDetailView, GroupsView, UnassignedUsersView, AddUnassignedMenu, template) ->

  class GroupCategoryView extends View

    template: template

    @child 'groupCategoryDetailView', '[data-view=groupCategoryDetail]'
    @child 'unassignedUsersView', '[data-view=unassignedUsers]'
    @child 'groupsView', '[data-view=groups]'

    els:
      '.filterable': '$filter'
      '.filterable-unassigned-users': '$filterUnassignedUsers'
      '.unassigned-users-heading': '$unassignedUsersHeading'
      '.groups-with-count': '$groupsHeading'
      '.section-select': '$courseSectionSelect'


    _previousSearchTerm = ""
    _previousSectionId = ""

    initialize: (options) ->
      if(ENV.sections.length > 0)
        @model.setCurrentSectionId(ENV.sections[0].id)
      @groups = @model.groups()
      # TODO: move all of these to GroupCategoriesView#createItemView
      options.groupCategoryDetailView ?= new GroupCategoryDetailView
        parentView: this,
        model: @model
        collection: @groups
      options.groupsView ?= @groupsView(options)
      options.unassignedUsersView ?= @unassignedUsersView(options)
      if progress = @model.get('progress')
        @model.progressModel.set progress
      super

    groupsView: (options) ->
      addUnassignedMenu = null
      if ENV.IS_LARGE_ROSTER
        users = @model.unassignedUsers()
        addUnassignedMenu = new AddUnassignedMenu collection: users
      new GroupsView {
        collection: @groups
        addUnassignedMenu
      }

    unassignedUsersView: (options) ->
      return false if ENV.IS_LARGE_ROSTER
      new UnassignedUsersView {
        category: @model
        collection: @model.unassignedUsers()
        groupsCollection: @groups
      }

    filterChange: (event) ->
      search_term = event.target.value
      return if search_term == _previousSearchTerm #Don't rerender if nothing has changed
      if _previousSectionId
        options = {section_id : _previousSectionId}
      @options.unassignedUsersView.setFilter(search_term, options)
      @_setUnassignedHeading(@originalCount) unless search_term.length >= 3
      _previousSearchTerm = search_term

    courseSectionChange: (event) ->
      course_section_id = event.target.value
      return if course_section_id == _previousSectionId #Don't rerender if nothing has changed
      if course_section_id
        options = {section_id : course_section_id, force_search : true}
      @options.unassignedUsersView.setFilter(_previousSearchTerm, options)
      @options.groupsView.setFilter(course_section_id)
      _previousSectionId = course_section_id

    attach: ->
      @model.on 'destroy', @remove, this
      @model.on 'change', => @groupsView.updateDetails()

      @model.on 'change:unassigned_users_count', @setUnassignedHeading, this
      @groups.on 'add remove reset', @setGroupsHeading, this

      @model.progressModel.on 'change:url', =>
        @model.progressModel.set({'completion': 0})
      @model.progressModel.on 'change', @render
      @model.on 'progressResolved', =>
        @model.fetch success: =>
          @model.groups().fetch()
          @model.unassignedUsers().fetch()
          @render()

    cacheEls: ->
      super

      if !@attachedFilter
        @$filterUnassignedUsers.on "keyup", _.debounce(@filterChange.bind(this), 300)
        @attachedFilter = true

      if !@attachedSectionSelect
        @$courseSectionSelect.on "load change", '.course_section_id', @courseSectionChange.bind(this)
        @attachedSectionSelect = true

      # need to be set before their afterRender's run (i.e. before this
      # view's afterRender)
      @groupsView.$externalFilter = @$filter
      @unassignedUsersView.$externalFilter = @$filterUnassignedUsers

    afterRender: ->
      @setUnassignedHeading()
      @setGroupsHeading()

    setUnassignedHeading: ->
      count = @model.unassignedUsersCount() ? 0
      @originalCount = @originalCount || count
      @_setUnassignedHeading(count)

    _setUnassignedHeading: (count) ->
      @unassignedUsersView.render() if @unassignedUsersView
      @$unassignedUsersHeading.text(
        if @model.get('allows_multiple_memberships')
          I18n.t('everyone', "Everyone (%{count})", {count})
        else if ENV.group_user_type is 'student'
          I18n.t('unassigned_students', "Unassigned Students (%{count})", {count})
        else
          I18n.t('unassigned_users', "Unassigned Users (%{count})", {count})
      )

    setGroupsHeading: ->
      count = @model.groupsCount()
      @$groupsHeading.text I18n.t("groups_count", "Groups (%{count})", {count})

    toJSON: ->
      json = @model.present()
      json.ENV = ENV
      json.sections = ENV.sections
      json.groupsAreSearchable = ENV.IS_LARGE_ROSTER and
                                 not json.randomlyAssignStudentsInProgress
      json

