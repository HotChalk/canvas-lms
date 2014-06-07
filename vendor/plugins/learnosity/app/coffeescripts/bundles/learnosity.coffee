require [
  'jquery'
  '//questions.learnosity.com'
], ($) ->
  @lrnActivities = []

  $(document).ready ->
    $("span.learnosity-response").each ->
      container = $(this).parent()
      lrnObject = LearnosityApp.init($(this).data("learnosity-request"))
      lrnActivities.push lrnObject
      refreshResponses = (event) =>
        if !!lrnObject.getResponses()
          responses = lrnObject.getResponses()
          scores = lrnObject.getScores()
          newVal = {
            'responses': responses,
            'scores': scores
          }
          newResponse = if $.isEmptyObject(responses) then '' else (JSON.stringify newVal)
          container.find('.response-holder').val(newResponse).trigger('change')
      container.delegate 'div.lrn input', 'change', refreshResponses
      container.delegate '[contenteditable]', 'blur', refreshResponses
