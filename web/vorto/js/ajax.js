//
// Copyright(C) 2017 Tositaka Teramoto
// Released under the MIT license
// http://opensource.org/licenses/mit-license.php

//////////////////////////////////////////////////////
// Ajax

function addPostParam(sParams, sParamName, sParamValue) {
	if (sParams.length > 0) {
		sParams += "&";
	}
	return sParams + encodeURIComponent(sParamName) + "=" 
		+ encodeURIComponent(sParamValue);
}

function addURLParam(sURL, sParamName, sParamValue) {
	sURL += (sURL.indexOf("?") == -1 ? "?" : "&");
	sURL += encodeURIComponent(sParamName) + "=" + encodeURIComponent(sParamValue);
	return sURL;   
}

// XMLHttRequest
function createXHR() {
	if (typeof XMLHttpRequest != "undefined") {
		return new XMLHttpRequest();
	}
	else if (window.ActiveXObject) {
		var arrSignatures = ["MSXML2.XMLHTTP.6.0", "MSXML2.XMLHTTP.3.0"];

		for (var i=0; i < arrSignatures.length; i++) {
			try {
				var oRequest = new ActiveXObject(arrSignatures[i]);
				return oRequest;
			} catch (oError) {
				//ignore
			}
		}

		//alert("ERR ");
		throw new Error("MSXML is not installed on your system.");
	}
}

function ajaxGet(url, callback, self) {
	var req = createXHR();
	if (callback) {
		// Async
		req.open("GET", url, true);
		req.onreadystatechange= function() {
			if (req.readyState==4 && req.status==200) {
				if (self)
					callback(req.responseText, self);
				else
					callback(req.responseText);
			}
		};
		req.send(null);
	} else {
		// Sync (callback=null)
		req.open("GET", url, false);
		req.onreadystatechange= function() {};
		req.send(null);
		return req.responseText;
	}
}

function ajaxPost(url, data, contentType, callback, self) {
	var req = createXHR();
	if (callback) {
		// Async
		req.open("POST", url, true);
		req.setRequestHeader("content-type", contentType);
		req.onreadystatechange= function() {
			if (req.readyState==4 && req.status==200) {
				if (self)
					callback(req.responseText, self);
				else
					callback(req.responseText);
			}
		};
		req.send(data);
	} else {
		// Sync (callback=null)
		req.open("POST", url, false);
		req.setRequestHeader("content-type", contentType);
		req.onreadystatechange= function() {};
		req.send(data);
		return req.responseText;
	}
}
