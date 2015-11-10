require [
  'jquery'
  'compiled/models/DiscussionTopic'
  'compiled/models/Announcement'
  'compiled/models/DueDateList'
  'compiled/models/Assignment'
  'compiled/views/DiscussionTopics/EditView'
  'compiled/views/assignments/DueDateOverride'
  'compiled/collections/AssignmentGroupCollection'
  'compiled/collections/SectionCollection'
  'compiled/str/splitAssetString'
  'grading_standards'
  'manage_groups'
], ($, DiscussionTopic, Announcement, DueDateList, Assignment, EditView,
OverrideView, AssignmentGroupCollection, SectionCollection,
splitAssetString) ->

  is_announcement = ENV.DISCUSSION_TOPIC.ATTRIBUTES?.is_announcement
  model = new (if is_announcement then Announcement else DiscussionTopic)(ENV.DISCUSSION_TOPIC.ATTRIBUTES, parse: true)
  model.urlRoot = ENV.DISCUSSION_TOPIC.URL_ROOT
  assignment = model.get('assignment')

  sectionList = new SectionCollection ENV.SECTION_LIST
  dueDateList = new DueDateList assignment.get('assignment_overrides'), sectionList, assignment

  discussionDueDateList = new DueDateList model.get('assignment_overrides'), sectionList, model
  discussionDueDateList.showDueDate = false

  [contextType, contextId] = splitAssetString ENV.context_asset_string
  view = new EditView
    model: model
    permissions: ENV.DISCUSSION_TOPIC.PERMISSIONS
    contextType: contextType
    views:
      'js-overrides': new OverrideView
        model: discussionDueDateList
        views: {}
      'js-assignment-overrides': new OverrideView
        model: dueDateList
        views: {}

  if contextType is 'courses' && !is_announcement && ENV.DISCUSSION_TOPIC.PERMISSIONS.CAN_CREATE_ASSIGNMENT
    (view.assignmentGroupCollection = new AssignmentGroupCollection).contextAssetString = ENV.context_asset_string

  $ ->
    view.render().$el.appendTo('#content')
    $('#discussion-title').focus()
    elements = $('.ic-Label')
    if is_announcement then control.innerHTML = 'Post to' for control in elements when control.innerHTML is 'Assign to'

  view
