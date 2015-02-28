library ipfs_interceptor;

import 'dart:html';
import 'dart:js';

// There is a Dart library for Chrome Apps and Extensions but it's pretty
// broken so we're best off just accessing the JS API directly.
JsObject contextMenusNamespace = context['chrome']['contextMenus'];
JsObject declarativeContentNamespace = context['chrome']['declarativeContent'];
JsObject pageActionNamespace = context['chrome']['pageAction'];
JsObject runtimeNamespace = context['chrome']['runtime'];
JsObject webRequestNamespace = context['chrome']['webRequest'];


void main() {
  addListenerToChromeEvent(runtimeNamespace, 'onInstalled', onInstalledAction);

  // A page action is the little icon that appears in the URL bar.
  addListenerToChromeEvent(pageActionNamespace, 'onClicked', pageActionOnClickedAction);

  addContextMenu();
  setupWebRequestRedirect();
}


void addContextMenu() {
  var urlMatch = ["http://localhost:*/ipfs/*", "http://localhost:*/ipns/*"];
  var props = new JsObject.jsify({
    'contexts': ['link'],

    // This should match the default_title under page_action in the manifest
    'title': 'Copy as IPFS link',

    'documentUrlPatterns': urlMatch,
    'targetUrlPatterns': urlMatch,
    'onclick': (JsObject info, JsObject tab) {
      addToClipboardAsIpfsUrl(info['linkUrl']);
    }
  });
  contextMenusNamespace.callMethod('create', [props]);
}


void addListenerToChromeEvent(JsObject namespace, String eventName, Function callback) {
  var dartifiedEvent = dartifyChromeEvent(namespace, eventName);
  dartifiedEvent.callMethod('addListener', [callback]);
}


void addToClipboard(String text) {
  // Yes this is a zany hack.
  var tempEl = document.createElement('textarea');
  document.body.append(tempEl);
  tempEl.value = text;
  tempEl.focus();
  tempEl.select();
  document.execCommand('copy', false, null);
  tempEl.remove();
}


String addToClipboardAsIpfsUrl(String localUrl) {
  var ipfsUrl = Uri.parse(localUrl).replace(host: 'gateway.ipfs.io', port: 80);
  addToClipboard(ipfsUrl.toString());
}


/**
 * This function exists purely because of a bug in the dart2js compiler. It
 * must be used to properly access a Chrome Event object. Without it, vague
 * meaningless errors when running as Javascript will crop up.
 * https://code.google.com/p/dart/issues/detail?id=20800
 */
JsObject dartifyChromeEvent(JsObject namespace, String eventName) {
  var event = namespace[eventName];
  JsObject dartifiedEvent;
  if (event is JsObject) {
    dartifiedEvent = event;
  } else {
    // Dart2JS glitch workaround https://code.google.com/p/dart/issues/detail?id=20800
    dartifiedEvent = new JsObject.fromBrowserObject(event);
  }

  return dartifiedEvent;
}


void onInstalledAction(JsObject details) {
  var pageStateMatcherArg = new JsObject.jsify({
    'pageUrl': {
      // Chrome has globbing available everywhere but here
      'originAndPathMatches': '^http://localhost(:[[:digit:]]+)?\\/(ipfs|ipns)\\/.+',
      'schemes': ['http']
  }});
  var rules = new JsObject.jsify([{
    'conditions': [
      new JsObject(declarativeContentNamespace['PageStateMatcher'], [pageStateMatcherArg])
    ],
    'actions': [
      new JsObject(declarativeContentNamespace['ShowPageAction']),
    ]
  }]);
  dartifyChromeEvent(declarativeContentNamespace,
                     'onPageChanged').callMethod('removeRules', [null, () {
      dartifyChromeEvent(declarativeContentNamespace,
                         'onPageChanged').callMethod('addRules', [rules]);
  }]);
}


void pageActionOnClickedAction(JsObject tab) {
  addToClipboardAsIpfsUrl(tab['url']);
}


void setupWebRequestRedirect() {
  dartifyChromeEvent(webRequestNamespace, 'onBeforeRequest').callMethod('addListener', [
    webRequestOnBeforeRequestAction,
    new JsObject.jsify({
      'urls': ['http://gateway.ipfs.io/ipfs/*', 'http://gateway.ipfs.io/ipns/*']
    }),
    new JsObject.jsify(['blocking'])
  ]);
}


JsObject webRequestOnBeforeRequestAction(JsObject data) {
  var ipfsUrl = data['url'];
  var localhostUrl = Uri.parse(ipfsUrl).replace(host: 'localhost', port: 8080);
  var response = {
    'redirectUrl': localhostUrl.toString()
  };
  return new JsObject.jsify(response);
}
