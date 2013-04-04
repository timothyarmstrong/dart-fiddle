import 'dart:html';
import 'dart:json' as JSON;
import 'dart:uri' as uri;

import 'package:js/js.dart' as js;

String getId() {
  var path = window.location.pathname;
  if (path == '/' || path.isEmpty) {
    return '';
  } else {
    return path.split('/')[1];
  }
}

void setId(String id) {
  window.history.pushState(null, '', '/$id');
}

void apiResponse(HttpRequest request) {
  query('#run').disabled = false;

  var data = JSON.parse(request.responseText);
  if (data.containsKey('error')) {
    window.alert(data['error']);
    return;
  }

  var id = data['id'];
  setId(id);

  sendStatusRequest(data['token']);
}

void statusResponse(HttpRequest request, String token) {
  var data = JSON.parse(request.responseText);
  print(data['status']);
  if (!data['last']) {
    sendStatusRequest(token);
  } else {
    var iframe = query('#result-panel iframe');
    iframe.src = '/files/${getId()}/';
  }
}

void sendStatusRequest(String token) {
  var request = new HttpRequest();
  request.open('GET', '/api/status/$token');
  request.onLoadEnd.listen((e) => statusResponse(request, token));
  request.send();
}

class _Document {
  Element editorElement;
  Element tabElement;
  var aceProxy; // TODO: What type is this?
  String filename;
  String filetype;
  bool renamable;

  _Document(this.editorElement, this.tabElement, this.aceProxy, this.filename, this.filetype, this.renamable);

  void makeActive() {
    editorElement.classes.add('active');
    tabElement.classes.add('active');
  }

  void makeInactive() {
    editorElement.classes.remove('active');
    tabElement.classes.remove('active');
  }

  /*Map<String, String> get contents() {
    var editorContents;
    js.scoped(() {
      //
    });
  }*/

}

class Editor {
  bool canCreateDocuments;
  String requiredSuffix;

  Element _root;

  Element _tabBar;
  Element _editorContainer;
  Element _statusBar;
  Element _newButton;

  _Document _activeDocument;

  // Map of filenames to their documents.
  Map<String, _Document> _documents = new Map();

  // Map of filetypes to the ACE modes
  Map<String, String> _filetypeToMode = {
    'Javascript': 'ace/mode/javascript',
    'HTML': 'ace/mode/html',
    'YAML': 'ace/mode/yaml',
    'Dart': 'ace/mode/javascript'
  };

  Editor(this._root, {this.canCreateDocuments: false}) {
    // Create initial editor structure.
    
    // Tab bar.
    _tabBar = new DivElement();
    _tabBar.classes.add('tab-bar');
    _root.append(_tabBar);

    // Container for the ACE editors.
    _editorContainer = new DivElement();
    _editorContainer.classes.add('editors');
    _root.append(_editorContainer);

    // Status bar.
    _statusBar = new DivElement();
    _statusBar.classes.add('status');
    _root.append(_statusBar);

    // TODO: Pass this setting in.
    if (canCreateDocuments) {
      _newButton = new DivElement();
      _newButton.classes.add('new');
      _newButton.text = "+";
      _tabBar.append(_newButton);

      _newButton.onClick.listen((e) {
        var input = askForFilename();
        createDocument(input['filename'], '', input['filetype']);
        switchToDocument(input['filename']);
      });
    }

  }

  // Returns the filename and filetype.
  Map<String, String> askForFilename() {
    // TODO: Use a better replacement for prompt
    var filename;
    do {
      js.scoped(() {
        filename = js.context.prompt('Filename?');
      });
    } while (filename == null || _documents.containsKey(filename));

    var filetype;
    if (filename.toLowerCase().endsWith('.dart')) {
      filetype = 'Dart';
    } else if (filename.toLowerCase().endsWith('.js')) {
      filetype = 'JavaScript';
    } else {
      filename = '$filename.dart';
      filetype = 'Dart';
    }
    return {
      'filename': filename,
      'filetype': filetype
    };
  }

  void createDocument(String filename, String content, String filetype, {renamable: true}) {
    // Tab.
    var tab = new DivElement();
    tab.classes.add('tab');
    tab.text = filename;
    tab.dataset['filename'] = filename;
    tab.title = filename;
    if (canCreateDocuments) {
      _tabBar.insertBefore(tab, _tabBar.query('.new'));
    } else {
      _tabBar.append(tab);
    }

    tab.onClick.listen((e) {
      var filename = e.currentTarget.dataset['filename'];
      switchToDocument(filename);
    });

    // User can rename file by double-clicking its tab.
    tab.onDoubleClick.listen((e) {
      var filename = e.currentTarget.dataset['filename'];
      var document = _documents[filename];
      if (document.renamable) {
        var input = askForFilename();
        document.filename = input['filename'];
        document.filetype = input['filetype'];
        tab.text = input['filename'];
        tab.dataset['filename'] = input['filename'];
        tab.title = input['filename'];
        _statusBar.text = input['filetype'];
        // Put this document back in the set of documents.
        _documents.remove(filename);
        _documents[input['filename']] = document;
      }
    });

    // ACE editor.
    var aceElement = new DivElement();
    aceElement.classes.add('editor');
    _editorContainer.append(aceElement);

    // Setup ACE.
    var aceProxy;
    js.scoped(() {
      aceProxy = js.context.ace.edit(aceElement);
      //aceProxy.setTheme('ace/theme/espresso');
      aceProxy.getSession().setMode(_filetypeToMode[filetype]);
      aceProxy.setShowPrintMargin(false);
      aceProxy.getSession().setTabSize(2);
      aceProxy.setHighlightActiveLine(false);
      aceProxy.setValue(content);
      aceProxy.clearSelection();

      js.retain(aceProxy);
    });

    js.scoped(() {
      //window.alert(aceProxy.getValue());
    });

    // Bundle everything up into a _Document.
    var document = new _Document(aceElement, tab, aceProxy, filename, filetype, renamable);

    if (_documents.isEmpty) {
      _activeDocument = document;
      _activeDocument.makeActive();
      _statusBar.text = _activeDocument.filetype;
    }

    // Remember this document.
    _documents[filename] = document;

  }

  // Changes the active tab.
  void switchToDocument(String filename) {
    _activeDocument.makeInactive();
    _activeDocument = _documents[filename];
    _activeDocument.makeActive();
    _statusBar.text = _activeDocument.filetype;
  }

  List<Map<String, String>> getDocumentsContents() {
    var retval = new List();
    _documents.forEach((filename, document) {
      var data = new Map();
      data['filename'] = filename;
      js.scoped(() {
        data['content'] = document.aceProxy.getValue();
      });
      retval.add(data);
    });
    return retval;
  }

}

main() {
  
  // Grab the initial data from the JavaScript.
  var initialData;
  js.scoped(() {
    initialData = JSON.parse(js.context.initialData);
  });

  // Create the editors.
  var dartEditor = new Editor(query('#dart-code'), canCreateDocuments: true);
  for (var file in initialData['dart']) {
    var renamable = file['filename'] != 'main.dart';
    dartEditor.createDocument(file['filename'], file['content'], file['type'], renamable: renamable);
  }
  var htmlEditor = new Editor(query('#html-code'));
  for (var file in initialData['html']) {
    htmlEditor.createDocument(file['filename'], file['content'], file['type'], renamable: false);
  }

  // Prepare the 'run' button.
  var runButton = query('#run');
  runButton.onClick.listen((e) { // TODO: use onClick.listen.
    // The data to send.
    var data = {
      'id': getId(),
      'dart': dartEditor.getDocumentsContents(),
      'html': htmlEditor.getDocumentsContents()
    };

    // Setup and send the API request.
    var request = new HttpRequest();
    request.open('POST', '/api/save');
    
    request.onLoadEnd.listen((e) => apiResponse(request));

    var formData = new FormData();
    formData.append('data', JSON.stringify(data));

    request.send(formData);

    runButton.disabled = true;
  });

  // Prepare the other buttons.
  query('#download').onClick.listen((e) {
    var message = "Unimplemented!\n"
"This button will allow you to download a .zip of all the files created so that"
" you can continue working on your local machine";
    window.alert(message);
  });
  query('#save').onClick.listen((e) {
var message = "Unimplemented!\n"
"I haven't fully decided on how this functionality will work. I like the idea of"
" being able to snapshot different revisions, but I don't love the way that"
" JSFiddle does it. Suggestions welcome.";
    window.alert(message);
  });
  query('#fork').onClick.listen((e) {
    var message = "Unimplemented!\n"
"This will simply generate a new ID and leave the old one where it was.";
    window.alert(message);
  });
}
