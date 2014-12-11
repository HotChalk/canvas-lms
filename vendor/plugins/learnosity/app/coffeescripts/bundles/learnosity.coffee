require [
  'jquery'
  '//questions.learnosity.com'
], ($) ->
  @lrnActivities = []

  $(document).ready ->
    $("span.learnosity-response").each ->
      container = $(this).parent()
      lrnObject = LearnosityApp.init($(this).data("learnosity-request"))
      lrnActivities.push {object: lrnObject, container: container, id: $(this).data("question-id")}

      # Set Learnosity question_holder divs to overflow:visible, otherwise some popup UI elements will be clipped
      $(this).closest(".question_holder").css("overflow", "visible")
    refreshResponses = () =>
      $(lrnActivities).each ->
        lrnObject = this['object']
        container = this['container']
        id = this['id']
        responses = lrnObject.getResponses()
        scores = lrnObject.getScores()
        newResponse = ''
        if !!responses && responses[id] && responses[id].value && (responses[id].value.length || typeof responses[id].value == 'object')
          newVal = {
            'responses': responses,
            'scores': scores
          }
          newResponse = JSON.stringify newVal
        container.find('.response-holder').val(newResponse).trigger('change')
    window.setInterval refreshResponses, 500
