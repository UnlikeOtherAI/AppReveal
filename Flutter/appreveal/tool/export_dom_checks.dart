import 'dart:convert';
import 'dart:io';
import 'package:appreveal/src/webview/dom_serializer.dart';

void main(List<String> arguments) {
  File(arguments.single).writeAsStringSync(jsonEncode({
    'missingRoot': DOMSerializer.dumpTreeJS(root: '#missing'),
    'click': DOMSerializer.clickJS('#button'),
    'disabledClick': DOMSerializer.clickJS('#disabled'),
    'type': DOMSerializer.typeJS('#input', 'line\nquote\'\\end', clear: true),
    'readonly': DOMSerializer.typeJS('#readonly', 'bad'),
    'wrongType': DOMSerializer.typeJS('#button', 'bad'),
    'select': DOMSerializer.selectJS('#select', 'b'),
    'missingOption': DOMSerializer.selectJS('#select', 'missing'),
    'toggle': DOMSerializer.toggleJS('#checkbox', true),
    'untoggleRadio': DOMSerializer.toggleJS('#radio', false),
    'wrongToggle': DOMSerializer.toggleJS('#button', true),
    'scroll': DOMSerializer.scrollToJS('#bottom'),
    'forms': DOMSerializer.formsJS(),
    'tree': DOMSerializer.dumpTreeJS(),
    'interactive': DOMSerializer.interactiveJS(),
    'query': DOMSerializer.queryJS('#input'),
    'text': DOMSerializer.textContentJS(),
    'find': DOMSerializer.findTextJS('Submit'),
    'links': DOMSerializer.linksJS(),
    'headings': DOMSerializer.headingsJS(),
    'images': DOMSerializer.imagesJS(),
    'tables': DOMSerializer.tablesJS(),
    'summary': DOMSerializer.summaryJS(),
  }));
}
