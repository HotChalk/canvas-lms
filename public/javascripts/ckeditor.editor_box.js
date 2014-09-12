// CKEditor-jQuery EditorBox plugin
// Called on a jQuery selector (should be a single object only)
// to initialize a CKEditor editor box in the place of the
// selected textarea: $("#edit").editorBox().  The textarea
// must have a unique id in order to function properly.
// editorBox():
// Initializes the object.  All other methods should
// only be called on an already-initialized box.
// editorBox('focus', [keepTrying])
//   Passes focus to the selected editor box.  Returns
//   true/false depending on whether the focus attempt was
//   successful.  If the editor box has not completely initialized
//   yet, then the focus will fail.  If keepTrying
//   is defined and true, the method will keep trying until
//   the focus attempt succeeds.
// editorBox('destroy')
//   Removes the CKEditor instance from the textarea.
// editorBox('toggle')
//   Toggles the CKEditor instance.  Switches back and forth between
//   the textarea and the CKEditor WYSIWYG.
// editorBox('get_code')
//   Returns the plaintext code contained in the textarea or WYSIGWYG.
// editorBox('set_code', code)
//   Sets the plaintext code content for the editor box.  Replaces ALL
//   content with the string value of code.
// editorBox('insert_code', code)
//   Inserts the string value of code at the current selection point.
// editorBox('create_link', options)
//   Creates an anchor link at the current selection point.  If anything
//   is selected, makes the selection a link, otherwise creates a link.
//   options.url is used for the href of the link, and options.title
//   will be the body of the link if no text is currently selected.

define([
  'i18nObj',
  'jquery',
  'compiled/editor/editorAccessibility', /* editorAccessibility */
  'INST', // for IE detection; need to handle links in a special way
  'ckeditor-jquery', // CKEditor
  'jqueryui/draggable' /* /\.draggable/ */,
  'jquery.instructure_misc_plugins' /* /\.indicate/ */,
  'vendor/jquery.scrollTo' /* /\.scrollTo/ */,
  'vendor/jquery.ba-tinypubsub',
  'vendor/scribd.view' /* scribd */
], function(I18nObj, $, EditorAccessibility, INST) {

  // TODO where is this used?
  var enableBookmarking = !!INST.browser.ie;
  $(document).ready(function() {
    enableBookmarking = !!INST.browser.ie;
  });

  function EditorBoxList() {
    this._textareas = {};
    this._editors = {};
    this._editor_boxes = {};
  }

  $.extend(EditorBoxList.prototype, {
    _addEditorBox: function(id, box) {
      $.publish('editorBox/add', id, box);
      this._editor_boxes[id] = box;
      this._editors[id] = CKEDITOR.instances[id];
      this._textareas[id] = $("textarea#" + id);
    },
    _removeEditorBox: function(id) {
      delete this._editor_boxes[id];
      delete this._editors[id];
      delete this._textareas[id];
      $.publish('editorBox/remove', id);
      if ($.isEmptyObject(this._editors)) $.publish('editorBox/removeAll');
    },
    _getTextArea: function(id) {
      if(!this._textareas[id]) {
        this._textareas[id] = $("textarea#" + id);
      }
      return this._textareas[id];
    },
    _getEditor: function(id) {
      if(!this._editors[id]) {
        this._editors[id] = CKEDITOR.instances[id];
      }
      return this._editors[id];
    },
    _getEditorBox: function(id) {
      return this._editor_boxes[id];
    }
  });

  var $instructureEditorBoxList = new EditorBoxList();

  function EditorBox(id, search_url, submit_url, content_url, options) {
    options = $.extend({}, options);

    var $textarea = $("#" + id);
    $textarea.data('enable_bookmarking', enableBookmarking);
    var width = $textarea.width();
    if(width == 0) {
      width = $textarea.closest(":visible").width();
    }

    // TODO handle extra buttons for plugins
    var instructure_buttons = ",instructure_image,instructure_equation";
    for(var idx in INST.editorButtons) {
      // maxVisibleEditorButtons should be the max number of external tool buttons
      // that are visible, INCLUDING the catchall "more external tools" button that
      // will appear if there are too many to show at once.
      if(INST.editorButtons.length <= INST.maxVisibleEditorButtons || idx < INST.maxVisibleEditorButtons - 1) {
        instructure_buttons = instructure_buttons + ",instructure_external_button_" + INST.editorButtons[idx].id;
      } else if(!instructure_buttons.match(/instructure_external_button_clump/)) {
        instructure_buttons = instructure_buttons + ",instructure_external_button_clump";
      }
    }
    if(INST && INST.allowMediaComments && (INST.kalturaSettings && !INST.kalturaSettings.hide_rte_button)) {
      instructure_buttons = instructure_buttons + ",instructure_record";
    }
    var equella_button = INST && INST.equellaEnabled ? ",instructure_equella" : "";
    instructure_buttons = instructure_buttons + equella_button;

    var buttons1 = "bold,italic,underline,forecolor,backcolor,removeformat,justifyleft,justifycenter,justifyright,bullist,outdent,indent,sup,sub,numlist,table,instructure_links,unlink" + instructure_buttons + ",fontsizeselect,formatselect";
    var buttons2 = "";
    var buttons3 = "";

    if (width < 359 && width > 0) {
      buttons1 = "bold,italic,underline,forecolor,backcolor,removeformat,justifyleft,justifycenter,justifyright";
      buttons2 = "outdent,indent,sup,sub,bullist,numlist,table,instructure_links,unlink" + instructure_buttons;
      buttons3 = "fontsizeselect,formatselect";
    } else if (width < 600) {
      buttons1 = "bold,italic,underline,forecolor,backcolor,removeformat,justifyleft,justifycenter,justifyright,outdent,indent,sup,sub,bullist,numlist";
      buttons2 = "table,instructure_links,unlink" + instructure_buttons + ",fontsizeselect,formatselect";
    }

    var ckOptions = $.extend({
      extraAllowedContent: "iframe[src|width|height|name|align|style|class|sandbox]",
      startupFocus: options.focus,
      /*
      plugins: "autolink,instructure_external_tools,instructure_contextmenu,instructure_links," +
               "instructure_embed,instructure_image,instructure_equation,instructure_record,instructure_equella," +
               "media,paste,table,inlinepopups",
      */
      on: {
        focus: function(evt) {
          var $editor = $(evt.editor.element);
          $(document).triggerHandler('editor_box_focus', $editor);
          $.publish('editorBox/focus', $editor);
        }
      }
    }, options.tinyOptions || {});

    $textarea.ckeditor(ckOptions);

    this._textarea =  $textarea;
    this._editor = null;
    this._id = id;
    this._searchURL = search_url;
    this._submitURL = submit_url;
    this._contentURL = content_url;
    $instructureEditorBoxList._addEditorBox(id, this);

    // TODO add instructureEmbed command
    /*
    editor.addCommand('instructureEmbed', function (search) {
      if (!initted) initShared();
      $editor = thisEditor; // set shared $editor so images are pasted into the correct editor

      loadFields();
      $box.dialog('open');

      if (search === 'flickr') $flickrLink.click();
    });
    */
  }

// --------------------------------------------------------------------

  var editorBoxIdCounter = 1;

  $.fn.editorBox = function(options, more_options) {
    var args = arguments;
    if(this.length > 1) {
      return this.each(function() {
        var $this = $(this);
        $this.editorBox.apply($this, args);
      });
    }

    var id = this.attr('id');
    if(typeof(options) == "string" && options != "create") {
      if(options == "get_code") {
        return this._getContentCode(more_options);
      } else if(options == "set_code") {
        this._setContentCode(more_options);
      } else if(options == "insert_code") {
        this._insertHTML(more_options);
      } else if(options == "create_link") {
        this._linkSelection(more_options);
      } else if(options == "focus") {
        return this._editorFocus(more_options);
      } else if(options == "toggle") {
        this._toggleView();
      } else if(options == "execute") {
        var arr = [];
        for(var idx = 1; idx < arguments.length; idx++) {
          arr.push(arguments[idx]);
        }
        return $.fn._execCommand.apply(this, arr);
      } else if(options == "destroy") {
        this._removeEditor(more_options);
      } else if(options == "is_dirty") {
        return $instructureEditorBoxList._getEditor(id).checkDirty();
      } else if(options == 'exists?') {
        return !!$instructureEditorBoxList._getEditor(id);
      }
      return this;
    }
    this.data('rich_text', true);
    if(!id) {
      id = 'editor_box_unique_id_' + editorBoxIdCounter++;
      this.attr('id', id);
    }
    if($instructureEditorBoxList._getEditor(id)) {
      this._setContentCode(this.val());
      return this;
    }
    var search_url = "";
    if(options && options.search_url) {
      search_url = options.search_url;
    }
    var box = new EditorBox(id, search_url, "", "", options);
    return this;
  };

  $.fn._execCommand = function() {
    var id = $(this).attr('id');
    var editor = $instructureEditorBoxList._getEditor(id);
    if(editor && editor.execCommand) {
      editor.execCommand.apply(editor, arguments);
    }
    return this;
  };

  $.fn._justGetCode = function() {
    var id = this.attr('id') || '';
    var content = '';
    try {
      content = $instructureEditorBoxList._getTextArea(id).val();
    } catch(e) {}
    return content;
  };

  $.fn._getContentCode = function(update) {
    if(update == true) {
      var content = this._justGetCode(); //""
      this._setContentCode(content);
    }
    return this._justGetCode();
  };

  $.fn._getSearchURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._searchURL;
  };

  $.fn._getSubmitURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._submitURL;
  };

  $.fn._getContentURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._contentURL;
  };

  $.fn._toggleView = function() {
    var id = this.attr('id');
    var editor = $instructureEditorBoxList._getEditor(id);
    editor.setMode(editor.mode === 'source' ? 'wysiwyg' : 'source');
  };

  $.fn._removeEditor = function() {
    var id = this.attr('id');
    this.data('rich_text', false);
    var editor = $instructureEditorBoxList._getEditor(id);
    editor.destroy();
    $instructureEditorBoxList._removeEditorBox(id);
  };

  $.fn._setContentCode = function(val) {
    var id = this.attr('id');
    $instructureEditorBoxList._getTextArea(id).val(val);
    $instructureEditorBoxList._getEditor(id).setData(val);
  };

  $.fn._insertHTML = function(html) {
    var id = this.attr('id');
    var editor = $instructureEditorBoxList._getEditor(id);
    editor.insertHtml(html);
  };

  $.fn._editorFocus = function() {
    var $element = this,
        id = $element.attr('id'),
        editor = $instructureEditorBoxList._getEditor(id);
    if(!editor ) {
      return false;
    }
    editor.focus();
    $.publish('editorBox/focus', $element);
    return true;
  };

  $.fn._linkSelection = function(options) {
    if(typeof(options) == "string") {
      options = {url: options};
    }
    var title = options.title;
    var url = options.url || "";
    if(url.match(/@/) && !url.match(/\//) && !url.match(/^mailto:/)) {
      url = "mailto:" + url;
    } else if(!url.match(/^\w+:\/\//) && !url.match(/^mailto:/) && !url.match(/^\//)) {
      url = "http://" + url;
    }
    var classes = options.classes || "";
    var defaultText = options.text || options.title || "Link";
    var target = options.target || null;
    var id = $(this).attr('id');
    if(url.indexOf("@") != -1) {
      options.file = false;
      options.image = false;
      if(url.indexOf("mailto:") != 0) {
        url = "mailto:" + url;
      }
    } else if (url.indexOf("/") == -1) {
      title = url;
      url = url.replace(/\s/g, "");
      url = location.href + url;
    }
    if(options.file) {
      classes += "instructure_file_link ";
    }
    if(options.scribdable) {
      classes += "instructure_scribd_file ";
    }
    var link_id = '';
    if(options.kaltura_entry_id && options.kaltura_media_type) {
      link_id = "media_comment_" + options.kaltura_entry_id;
      if(options.kaltura_media_type == 'video') {
        classes += "instructure_video_link ";
      } else {
        classes += "instructure_audio_link ";
      }
    }
    if(options.image) {
      classes += "instructure_image_thumbnail ";
    }
    classes = $.unique(classes.split(/\s+/)).join(" ");
    var selectionText = "";
    var editor = $instructureEditorBoxList._getEditor(id);
    if(enableBookmarking && this.data('last_bookmark')) {
      editor.getSelection().selectBookmarks(this.data('last_bookmark'));
    }
    var selection = editor.getSelection();
    var anchor = selection.getNode();
    while(anchor.nodeName != 'A' && anchor.nodeName != 'BODY' && anchor.parentNode) {
      anchor = anchor.parentNode;
    }
    if(anchor.nodeName != 'A') { anchor = null; }

    var selectedContent = selection.getContent();
    if(!selectedContent || selectedContent == "") {
      if(anchor) {
        $(anchor).attr({
          href: url,
          title: title || '',
          id: link_id,
          'class': classes,
          target: target
        });
      } else {
        selectionText = defaultText;
        var $div = $("<div/>");
        $div.append($("<a/>", {id: link_id, target: target, title: title, href: url, 'class': classes}).text(selectionText));
        editor.insertHtml($div.html());
      }
    } else {
      editor.insertElement($("<a/>", {target: (target || ''), title: (title || ''), href: url, 'class': classes, 'id': link_id}));
    }
  };

});
