library dartfiddle;

import 'dart:async';
import 'dart:io';
import 'dart:json' as JSON;
import 'dart:math';

part 'status_response_manager.dart';

// GLOBALS

var responseManager = new StatusResponseManager();

// UTIL FUNCTIONS.

String addslashes(String s) {
  return s.replaceAll(r'\', r'\\') // Backslashes
          .replaceAll(r'"', r'\"') // Double quotes
          .replaceAll(r"'", r"\'") // Single quotes
          .replaceAll(r"/", r"\\/"); // Forward slashes (for some reason)
}

// TODO: Fix the type this takes.
Future<Map<String, String>> getFormDataJsonFromInputStream(Stream input) {
  var completer = new Completer();

  var buffer = new List<String>();

  input.listen((data) => buffer.add(new String.fromCharCodes(data)), onDone: () {
    var fullString = buffer.join('');
    completer.complete(JSON.parse(fullString.substring(fullString.indexOf('{'), fullString.lastIndexOf('}') + 1)));
  });

  // TODO: Error handling.

  return completer.future;
}

// Generate the ID used in the URL to identify a particular fiddle. The
// generated ID is seven characters long, alternative between consonants and
// vowels (some have been removed to make it more pronouncable and memorable).
// TODO: Maybe come up with a better version? Currently 8'192'000 possibilities.
String generateId() {
  final consonants = 'bcdfgjklmnprstvz';
  final vowels = 'aeiou';
  var id = new StringBuffer();
  var random = new Random();

  while (id.length < 7) {
    if (id.length % 2 == 0) {
      id.write(consonants[random.nextInt(consonants.length - 1)]);
    } else {
      id.write(vowels[random.nextInt(vowels.length - 1)]);
    }
  }
  return id.toString();
}

// Generate a token to identify a request so that the status of that request can
// be queried.
// TODO: Consider a better algorithm?
String generateRequestToken() {
  var token = new StringBuffer();
  var random = new Random();
  while (token.length < 32) {
    token.write(random.nextInt(9));
  }
  return token.toString();
}

// Checks if the id is valid. This is not (currently) a strict check of the
// format, but it checks that the potential ID is safe enough to perform
// filesystem checks with.
bool isValidId(String id) {
  final pattern = new RegExp(r'^[a-z]{7}$', caseSensitive: false);
  return pattern.hasMatch(id);
}



// PATH HANDLERS

// Handle API calls.
void handleApiCall(request) {
  getFormDataJsonFromInputStream(request)
      .then((Map<String, String> data) {
    // TODO: This function currently performs synchronous filesystem operations.
    // It should be moved to an isolate so that this operations don't block
    // server requests.

    var id = data['id'];
    var dir;

    var needToRunPub = false;

    if (id.isEmpty) {
      do {
        id = generateId();     
        dir = new Directory('./files/$id/');
      } while (dir.existsSync());

      dir.createSync(recursive: true);

      // TODO: Copy over the default pub installation instead of having to run
      // pub on first run.
      needToRunPub = true;

    } else {
      if (!isValidId(id)) {
        sendApiError(request.response, 'Invalid ID.');
        return;
      }

      dir = new Directory('./files/$id/');

      // If the directory does not exist, then this ID does not exist.
      if (!dir.existsSync()) {
        sendApiError(request.response, 'Unknown ID.');
        return;
      }

      // Before we delete the old files, let's compare the old pubspec to the
      // new one.
      try {
        // TODO: Validity.
        var newPubspecContents = data['html'].firstWhere((fileInfo) {
          return fileInfo['filename'] == 'pubspec.yaml';
        })['content'];

        var existingPubspec =
            new File.fromPath(new Path('./files/$id/pubspec.yaml'));
        if (existingPubspec.existsSync()) {
          if (newPubspecContents != existingPubspec.readAsStringSync()) {
            needToRunPub = true;
          }
        } else {
          needToRunPub = true;
        }
      } on StateError {
        // No pubspec submitted, for some reason. But that's fine.
        // TODO: Should we log this? I don't really care.
      }

      // Delete all the files in this directory so that we can start fresh. I
      // only delete direct children, not what exists in the package directory.

      var files = dir.listSync();
      for (var file in files) {
        // Only delete files that are actual file objects, not directories.
        if (file is File) {
          file.deleteSync();
        }
      }
      
    }

    // Now that we've established the ID, we can return this result and the rest
    // of the updates come from status requests.
    var token = generateRequestToken();
    var initialResponse = {
      'id': id,
      'token': token
    };
    request.response.headers.set(HttpHeaders.CONTENT_TYPE, 'application/json');
    request.response.write(JSON.stringify(initialResponse));
    request.response.close();

    // We now have an empty directory that we can write into.
    // Write the input files to disk.
    // TODO: Filename filtering?
    // TODO: Check for correctness of data, otherwise we could crash the server.
    for (var fileInfo in data['dart']) {
      var file = new File.fromPath(new Path('./files/$id/${fileInfo['filename']}'));
      file.createSync();
      file.writeAsStringSync(fileInfo['content']);
    }

    for (var fileInfo in data['html']) {
      var file = new File.fromPath(new Path('./files/$id/${fileInfo['filename']}'));
      file.createSync();
      file.writeAsStringSync(fileInfo['content']);
    }

    // This function runs Pub if necessary, returning a future either way.
    Future maybeRunPub() {
      if (needToRunPub) {
        responseManager.addStatus(
            new Status(message: 'Running Pub...', step: 1), token);
        return Process.run('../../dart-sdk/bin/pub', ['install'], workingDirectory: './files/$id/');
      }
      return new Future.value();
    }

    // TODO: Handle Pub or dart2js errors.
    maybeRunPub()
      .then((_) {
        responseManager.addStatus(
            new Status(message: 'Running dart2js...', step: 2, dartiumDone: true), token);
        return new Future.value();
      })
      .then((_) {
        return Process.run('./dart-sdk/bin/dart2js', ['-o./files/$id/main.dart.js', './files/$id/main.dart']);
      })
      .then((result) {
        if (result.exitCode != 0) {
          print('Warning: dart2js encountered an error:\n${result.stdout}')
        }
        responseManager.addStatus(
            new Status(message: 'Completed', step: 3, dartiumDone: true, last: true), token);
      }).catchError((_) {

      });
  });
}

// Handle requests for the status of a save operation.
void handleStatusRequest(request) {
  // TODO: Validity.
  var pathParts = request.uri.path.split('/');
  var token = pathParts[pathParts.length - 1];
  responseManager.addResponse(request.response, token);
}

// Handle requests for the application.
void handleAppRequest(request) {
  // Get the ID.
  var id = '';
  var path = new Path(request.uri.path);
  if (path.segments().length == 1) {
    id = path.segments()[0];
  }

  // Ensure that this ID exists.
  if (!id.isEmpty) {
    if (!new Directory('./files/$id.').existsSync()) {
      request.response.headers.set(HttpHeaders.LOCATION, '/');
      request.response.statusCode = 302;
      request.response.close();
      return;
    }
  }

  var dartFiles = [];
  var htmlFiles = [];
  var iframeSource;
  if (id.isEmpty) {
    dartFiles.add(new File.fromPath(new Path('./templates/main.dart')));
    htmlFiles.add(new File.fromPath(new Path('./templates/index.html')));
    htmlFiles.add(new File.fromPath(new Path('./templates/pubspec.yaml')));
    iframeSource = '/static/special/default.html';
  } else {
    var files = new Directory('./files/$id').listSync();
    // Go ahead and add main.dart in first. We can remove it later if we don't
    // find it (this is a hack because I can't prepend to the list).
    dartFiles.add(new File.fromPath(new Path('./files/$id/main.dart')));
    bool foundMain = false;

    for (var file in files) {
      // We don't care about Directories.
      if (file is File) {
        var name = new Path(file.path).filename.toLowerCase();
        if (name == 'main.dart') {
          foundMain = true;
        } else if (name.contains('.dart.js')) {
          // PASS: Don't want this file because it's one of the compiled output.
          // TODO: Probably do this more intelligently.
        } else if (name.endsWith('.dart') ||
                   name.endsWith('.js')) {
          dartFiles.add(file);
        } else if (name.endsWith('.html') ||
                   name.endsWith('.yaml')) {
          htmlFiles.add(file);
        } else {
          // Unrecognized file type, so let's skip it.
          continue;
        }
      }
    }

    if (!foundMain) {
      dartFiles.removeAt(0);
    }

    iframeSource = '/files/$id/';
  }

  var dartCompleter = new Completer();
  var htmlCompleter = new Completer();

  var dartFilesRead = Future.wait(dartFiles.map((file) {
    return file.readAsString();
  }));

  var htmlFilesRead = Future.wait(htmlFiles.map((file) {
    return file.readAsString();
  }));


  // Fetch the files the we need.
  Future.wait([
    new File('./templates/app.html').readAsString(),
    dartFilesRead,
    htmlFilesRead
  ]).then((files) {
    var appFile = files[0];
    var dartFileContents = files[1];
    var htmlFileContents = files[2];

    // TODO: Dynamic based on actual files, which is hard because they will be stored on another fileserver.
    // Probably will need a database holding what they are.

    var initialData = {
      'id': id,
      'dart': [],
      'html': []
    };

    // TODO: This logic is kinda brittle. I hate pulling things out of the same
    // position from different arrays and mashing them together.

    for (int i = 0; i < dartFiles.length; i++) {
      var filename = new Path(dartFiles[i].path).filename;
      var content = dartFileContents[i];
      var type = 'Text';
      if (filename.endsWith('.js')) {
        type = 'JavaScript';
      } else if (filename.endsWith('.dart')) {
        type = 'Dart';
      }
      initialData['dart'].add({
        'filename': filename,
        'content': content,
        'type': type
      });
    }

    for (int i = 0; i < htmlFiles.length; i++) {
      var filename = new Path(htmlFiles[i].path).filename;
      var content = htmlFileContents[i];
      var type = 'Text';
      if (filename.endsWith('.html')) {
        type = 'HTML';
      } else if (filename.endsWith('.yaml')) {
        type = 'YAML';
      }
      initialData['html'].add({
        'filename': filename,
        'content': content,
        'type': type
      });
    }

    // Put the initial data JSON into a JavaScript variable in the page.
    var serialized = addslashes(JSON.stringify(initialData));
    appFile = appFile.replaceAll(r'{{ initialData }}', serialized);
    appFile = appFile.replaceAll(r'{{ iframeSource }}', iframeSource);

    request.response.write(appFile);
    request.response.close();
  });
}

// Handle static file requests.
void handleStaticFileRequest(request) {
  var filetypeMap = {
    'css': 'text/css',
    'js': 'application/javascript',
    'dart': 'application/dart',
    'json': 'application/json'
  };

  // Filter the path.
  var path = new Path('./${request.uri.path}').canonicalize();
  if (path.segments()[0] != 'static') { // TODO: potential NPE. // TODO: What if there is a dir higher up named static?
    print('no longer in static');
    send404(request);
  }
  // Send the file, if it exists.
  var file = new File.fromPath(path);
  file.exists().then((bool exists) {
    if (exists) {
      if (filetypeMap.containsKey(path.extension)) {
        request.response.headers.set(HttpHeaders.CONTENT_TYPE, filetypeMap[path.extension]);
      }
      file.openRead().pipe(request.response);
    } else {
      print('file does not exist');
      send404(request);
    }
  });
}

// Handle requests for created files. This is currently a copy-paste of above.
// TODO: This will change or be removed once we change were files are kept.
void handleFileRequest(request) {
  var filetypeMap = {
    'css': 'text/css',
    'js': 'application/javascript',
    'dart': 'application/dart',
    'json': 'application/json'
  };

  // Filter the path.
  var path = new Path('./${request.uri.path}').canonicalize();
  if (path.segments()[0] != 'files') { // TODO: potential NPE. // TODO: What if there is a dir higher up named static?
    print('no longer in files');
    send404(request);
  }
  // Send the file, if it exists.
  // TODO: Clean up this nastiness.
  var file = new File.fromPath(path);
  file.exists().then((bool exists) {
    if (exists) {
      if (filetypeMap.containsKey(path.extension)) {
        request.response.headers.set(
            HttpHeaders.CONTENT_TYPE, filetypeMap[path.extension]);
      }
      file.openRead().pipe(request.response);
    } else {
      // It might be a directory, so try serving its index.
      file = new File.fromPath(new Path('$path/index.html'));
      file.exists().then((bool exists) {
        if (exists) {
          if (filetypeMap.containsKey(path.extension)) {
            request.response.headers.set(
                HttpHeaders.CONTENT_TYPE, filetypeMap['html']);
          }
          file.openRead().pipe(request.response);
        } else {
          print('file does not exist');
          send404(request);
        }
      });
    }
  });
}

// ERROR HANDLING

// Normal 404 response.
void send404(request) {
  print('404: ${request.method}: ${request.uri.path}');
  // TODO: 404 code.
  request.response.statusCode = HttpStatus.NOT_FOUND;
  request.response.write("404'd");
  request.response.close();
}

// API Error
void sendApiError(response, [message = 'An error occurred.']) {
  // TODO: Which status to use? Catch on the other end too?
  // response.statusCode = statusCode;
  response.headers.set(HttpHeaders.CONTENT_TYPE, 'application/json');
  var message = {
    'error': message
  };
  response.write(JSON.stringify(message));
  response.close();
}

main() {
  var port = Platform.environment['PORT'] != null ?
               int.parse(Platform.environment['PORT']) : 3000;

  HttpServer.bind('0.0.0.0', port).then((HttpServer server) {
    print('Server started on port: ${port}');
    server.listen((HttpRequest request) {
      // Perform routing.
      // TODO: Use a routing library?
      var segments = new Path(request.uri.path).segments();
      if (request.uri.path.startsWith('/static/') && request.method == 'GET') {
        handleStaticFileRequest(request);
      } else if (request.uri.path.startsWith('/files/') &&
                 request.method == 'GET') {
        handleFileRequest(request);
      } else if (request.uri.path == '/api/save' && request.method == 'POST') {
        handleApiCall(request);
      } else if (request.uri.path.startsWith('/api/status/') &&
                 request.method == 'GET') {
        handleStatusRequest(request);
      } else if (segments.length == 0 || (segments.length == 1 &&
                 new RegExp(r'^[a-z]{7}$').hasMatch(segments[0]))) {
        // Requests for the application, either the root or including an ID.
        handleAppRequest(request);
      } else {
        // Default request handler.
        send404(request);
      }
    });
  });
}
