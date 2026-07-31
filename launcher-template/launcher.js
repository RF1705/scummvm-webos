(function () {
  "use strict";

  var target = "__SCUMMVM_TARGET__";
  var bridge = new PalmServiceBridge();
  bridge.onservicecallback = function () {
    window.close();
  };
  bridge.call(
    "luna://com.webos.applicationManager/launch",
    JSON.stringify({
      id: "org.scummvm.scummvm",
      params: { target: target }
    })
  );

  setTimeout(function () {
    window.close();
  }, 3000);
}());
