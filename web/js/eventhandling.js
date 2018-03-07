//
// Public domain
// Written by Tositaka Teramoto, 2017

///////////////////////////////////
// Event handling

function isIE() {
	return (navigator.userAgent.indexOf("MSIE") >= 0);
}

function addEventHandler(elem, evtname, handler) {
	if (isIE())
		elem.attachEvent("on"+evtname, handler);
	else
		elem.addEventListener(evtname, handler, false);
}
function removeEventHandler(elem, evtname, handler) {
	if (isIE())
		elem.detachEvent(evtname, handler);
	else
		elem.removeEventListener(evtname, handler, false);
}
