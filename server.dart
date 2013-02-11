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

Future<Map<String, String>> getFormDataJsonFromInputStream(InputStream input) {
  var completer = new Completer();

  var buffer = new List<String>();

  input.onData = () => buffer.add(new String.fromCharCodes(input.read()));

  input.onClosed = () {
    var fullString = buffer.join('');
    completer.complete(JSON.parse(fullString.slice(fullString.indexOf('{'), fullString.lastIndexOf('}') + 1)));
  };

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
      id.add(consonants[random.nextInt(consonants.length - 1)]);
    } else {
      id.add(vowels[random.nextInt(vowels.length - 1)]);
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
    token.add(random.nextInt(9));
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
void handleApiCall(request, response) {
  getFormDataJsonFromInputStream(request.inputStream).then((Map<String, String> data) {
    // TODO: This function currently performs synchronous filesystem operations.
    // It should be moved to an isolate so that this operations don't block
    // server requests.

    var id = data['id'];
    var dir;

    if (id.isEmpty) {
      do {
        id = generateId();     
        dir = new Directory('./files/$id/');
      } while (dir.existsSync());

      dir.createSync(recursive: true);

    } else {
      if (!isValidId(id)) {
        sendApiError(response, 'Invalid ID.');
        return;
      }

      dir = new Directory('./files/$id/');

      // If the directory does not exist, then this ID does not exist.
      if (!dir.existsSync()) {
        sendApiError(response, 'Unknown ID.');
        return;
      }

      // Delete all the files in this directory so that we can start fresh.
      // This is done by delete-then-recreate.
      // TODO: Working incrementally.

      dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      
    }

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

    // TODO: dart2js compilation.
    Process.run('./dart-sdk/bin/dart2js', ['-o./files/$id/main.dart.js', './files/$id/main.dart']).then((result) {

      // TODO: Handle error of ProcessResult.

      // Success.
      response.headers.set(HttpHeaders.CONTENT_TYPE, 'application/json');
      var message = {
        'success': true,
        'id': id
      };
      response.outputStream.writeString(JSON.stringify(message));
      response.outputStream.close();
    });
  });
}

// Handle requests for the application.
void handleAppRequest(request, response) {
  // Get the ID.
  var id = '';
  var path = new Path(request.path);
  if (path.segments().length == 1) {
    id = path.segments()[0];
  }

  // TODO: Ensure that this ID exists.

  var dartFilename, htmlFilename, pubspecFilename, iframeSource;
  if (id.isEmpty) {
    dartFilename = './templates/default_dart.txt';
    htmlFilename = './templates/default_html.txt';
    pubspecFilename = './templates/default_pubspec.txt';
    iframeSource = '/static/special/default.html';
  } else {
    dartFilename = './files/$id/main.dart';
    htmlFilename = './files/$id/index.html';
    pubspecFilename = './files/$id/pubspec.yaml'; 
    iframeSource = '/files/$id/';
  }

  // Fetch the files the we need.
  Future.wait([
    new File('./templates/app.html').readAsString(),
    new File(dartFilename).readAsString(),
    new File(htmlFilename).readAsString(),
    new File(pubspecFilename).readAsString()
  ]).then((files) {
    var appFile = files[0];
    var dartFile = files[1];
    var htmlFile = files[2];
    var pubspecFile = files[3];

    // TODO: Dynamic based on actual files, which is hard because they will be stored on another fileserver.
    // Probably will need a database holding what they are.
    var initialData = {
      'id': id,
      'dart': [
        {
          'filename': 'main.dart',
          'content': dartFile,
          'type': 'Dart'
        }
      ],
      'html': [
        {
          'filename': 'index.html',
          'content': htmlFile,
          'type': 'HTML'
        },
        {
          'filename': 'pubspec.yaml',
          'content': pubspecFile,
          'type': 'YAML'
        }
      ]
    };

    var serialized = addslashes(JSON.stringify(initialData));
    appFile = appFile.replaceAll(r'{{ initialData }}', serialized);
    appFile = appFile.replaceAll(r'{{ iframeSource }}', iframeSource);

    response.outputStream.writeString(appFile);
    response.outputStream.close();
  });
}

// Handle static file requests.
void handleStaticFileRequest(request, response) {
  var filetypeMap = {
    'css': 'text/css',
    'js': 'application/javascript',
    'dart': 'application/dart',
    'json': 'application/json'
  };

  // Filter the path.
  var path = new Path('./${request.path}').canonicalize();
  if (path.segments()[0] != 'static') { // TODO: potential NPE. // TODO: What if there is a dir higher up named static?
    print('no longer in static');
    send404(response);
  }
  // Send the file, if it exists.
  var file = new File.fromPath(path);
  file.exists().then((bool exists) {
    if (exists) {
      if (filetypeMap.containsKey(path.extension)) {
        response.headers.set(HttpHeaders.CONTENT_TYPE, filetypeMap[path.extension]);
      }
      file.openInputStream().pipe(response.outputStream);
    } else {
      print('file does not exist');
      send404(response);
    }
  });
}

// Handle requests for created files. This is currently a copy-paste of above.
// TODO: This will change or be removed once we change were files are kept.
void handleFileRequest(request, response) {
  var filetypeMap = {
    'css': 'text/css',
    'js': 'application/javascript',
    'dart': 'application/dart',
    'json': 'application/json'
  };

  // Filter the path.
  var path = new Path('./${request.path}').canonicalize();
  if (path.segments()[0] != 'files') { // TODO: potential NPE. // TODO: What if there is a dir higher up named static?
    print('no longer in files');
    send404(response);
  }
  // Send the file, if it exists.
  // TODO: Clean up this nastiness.
  var file = new File.fromPath(path);
  file.exists().then((bool exists) {
    if (exists) {
      if (filetypeMap.containsKey(path.extension)) {
        response.headers.set(HttpHeaders.CONTENT_TYPE, filetypeMap[path.extension]);
      }
      file.openInputStream().pipe(response.outputStream);
    } else {
      // It might be a directory, so try serving its index.
      file = new File.fromPath(new Path('$path/index.html'));
      file.exists().then((bool exists) {
        if (exists) {
          if (filetypeMap.containsKey(path.extension)) {
            response.headers.set(HttpHeaders.CONTENT_TYPE, filetypeMap['html']);
          }
          file.openInputStream().pipe(response.outputStream);
        } else {
          print('file does not exist');
          send404(response);
        }
      });
    }
  });
}

// ERROR HANDLING

// Normal 404 response.
void send404(response) {
  // TODO: 404 code.
  response.statusCode = HttpStatus.NOT_FOUND;
  response.outputStream.writeString("404'd");
  response.outputStream.close();
}

// API Error
void sendApiError(response, [message = 'An error occurred.']) {
  // TODO: Which status to use? Catch on the other end too?
  // response.statusCode = statusCode;
  response.headers.set(HttpHeaders.CONTENT_TYPE, 'application/json');
  var message = {
    'error': message
  };
  response.outputStream.writeString(JSON.stringify(message));
  response.outputStream.close();
}

main() {
  var server = new HttpServer();
  var port = int.parse(Platform.environment['PORT']);
  server.listen('0.0.0.0', port);
  print('Server started on port: ${port}');

  // Setup static request handler.
  server.addRequestHandler((request) {
    if (request.path.startsWith('/static/') && request.method == 'GET') {
      return true;
    }
    return false;
  }, handleStaticFileRequest);

  // Setup handler for the created files.
  server.addRequestHandler((request) {
    if (request.path.startsWith('/files/') && request.method == 'GET') {
      return true;
    }
    return false;
  }, handleFileRequest);

  // Setup API request handler.
  server.addRequestHandler((request) {
    if (request.path == '/api/save' && request.method == 'POST') {
      return true;
    }
    return false;
  }, handleApiCall);

  // Setup requests for the application, either the root or including an ID.
  server.addRequestHandler((request) {
    var segments = new Path(request.path).segments();
    if (segments.length == 0 || (segments.length == 1 && new RegExp(r'^[a-z]{7}$').hasMatch(segments[0]))) {
      return true;
    }
    return false;
  }, handleAppRequest);

  // Handle all other requests.
  server.defaultRequestHandler = (HttpRequest request, HttpResponse response) {
    if (request.path == '/favicon.ico') {
      // TODO: Handle favicon request.
      print('This is a favicon request.');
    }

    send404(response);

    /* response.headers.set(HttpHeaders.CONTENT_TYPE, 'text/html');
    response.outputStream.writeString('Default request handler');
    response.outputStream.close(); */
  };
}
