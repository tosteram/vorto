/*
File	regilo.js
		Elektronikaj Esperantaj Vortaroj kun retumilo
Date:
2014-07-09	Espvortaroj version 1.0
2014-07-31	version 2.0
2014-08-03~15	v2.1
2015-05-15~23	v2.2 link to "vorto:xxx"; do search after selecting from history. 
					search history
	06-15	use cookie ??;
2018-01-13	V3.0 Online dictionaries

Copyright (C) 2014-2018, Tositaka TERAMOTO & FUKUMOTO Hirotsugu.
Permission to use, copy, modify, and distribute this software and 
its documentation for any purpose (including commercial use) is hereby granted 
without fee, provided that the above copyright notice appear in all 
copies and that both that copyright notice and this permission 
notice appear in supporting documentation.
This file is provided "as is" without express or implied warranty.
*/

//--- constants ---
var IMG_add="sistem_img/Add20.png";
var IMG_remove="sistem_img/Remove20.png";
var IMG_open="sistem_img/Open24.png";
var IMG_closed="sistem_img/Closed24.png";
var IMG_book="sistem_img/Book24.png";
var IMG_books="sistem_img/Books24.png";
var IMG_Find="sistem_img/Find24.png";
//var IMG_FindMode ="sistem_img/FindMode.png";
//var IMG_FindModeX="sistem_img/FindModeX.png";
var IMG_Pool="sistem_img/Open24.png";
var IMG_PoolX="sistem_img/FolderX24.png";
var IMG_Colorize="sistem_img/Colorize24.png";
var IMG_ColorizeX="sistem_img/ColorizeX24.png";
var Limit= 500;	//max number of records on a page
var MaxPages= 1;
var MatchPrefix= "abc_";
var MatchPartial= "_abc_";
var MatchWord= "abc";
//-- dictionary specific functions --
var DictFuncs= {
	'no_conv': no_conv,
	'chapeligu':chapeligu,
	'romaji_kana':romaji_kana,			// ja-eo
	'makeEntry_std':makeEntry_std,
	'makeEntry_std2':makeEntry_std2,
	'makeDef_plain':makeDef_plain,
	'makeDef_plain2':makeDef_plain2,	// ja-eo
	'makeDef_html':makeDef_html
	};

//--- global variables ---
var Dictionaries= {
	// load the data from the Server
	// shortname:
	//		{dictid:(dict ID), name:(name), edition:(version), author:(author),
	//		 langs:(langs), text:(format), color:(color), remark:(rmark),
	//		 conv1:..., conv2:..., makeEntry:..., makeDef:...,
	//		 idx:(index), chk:(chk elem)
	//		}
};
var DefaultDicts= [];	//list of shortnames (Save to Cookie)
var SearchHistory= [];
var CompStrFunc= null;
var SchRec={ //Search Struct::
	//str:string
	//range: one of "entries","entiretext","root"
	//match: one of "prefix","partial","complet","word"
	//offset: 0,n*Limit,...
	//limit: Limit
	//sort: "none", "local", or "esperanto"
	//currentPage:(1..MaxPages), pages:(1..MaxPages), nhits:(0..Limit)
	//dicts:[shortname,...]
};
//options
var Opts= {
	//'showFindMode':true,
	'usePool':false,
	'colorize':false
}

//-------------------------------------

window.onload= function() {
	// Cookie
	var cookie= getCookie();
	DefaultDicts= cookie["defaultDicts"];
	SearchHistory= cookie["schHistory"];

	//language
	if (!lang_file) {
		try {
			var lang= (navigator.browserLanguage || navigator.language ||
					navigator.userLanguage).substr(0,2);
			var i;
			for (i=0; i<available_langs.length; ++i) {
				if (lang==available_langs[i]) {
					lang_file= "lang_"+lang+".js";
					break;
				}
			}
		} catch(e) {
			;
		}
		if (!lang_file)
			lang_file="lang_eo.js";
	}
	var script= document.createElement("script");
	script.type= "text/javascript";
	script.src= "js/" + lang_file;
	document.body.appendChild(script);
	//-->callback_lang() will be called when load completed.

	// position of search mode
	var modeElem= document.getElementById("searchMode");
	var defpane= document.getElementById("defpane");
	if (window.innerWidth<500) {
		modeElem.style.display= "block";
		defpane.style.top="105px";
	} else {
		modeElem.style.display= "inline";
		defpane.style.top="80px";
	}

	//set the defaults
	document.body.style.fontFamily= defaultOpts["font_family"];
	document.body.style.fontSize= defaultOpts["font_size"];
	document.getElementById("search_range").value= defaultOpts["searchRange"];
//	Opts.showFindMode= !defaultOpts.showFindMode;
	Opts.usePool= !defaultOpts.usePool;
	Opts.colorize= !defaultOpts.colorize;
//	toggleFindMode();
	togglePool();
	toggleColorize();

	//event handlers
	addEventHandler(document.getElementById("searchstr"), "keydown", inputSearchStr);
	addEventHandler(document.getElementById("selectSchHistory"), "keydown", schHistoryKeyPress);
	addEventHandler(document.getElementById("poolContent"), "click", onDefClicked);
	addEventHandler(document.getElementById("defs"), "click", onDefClicked);

	var imgs=document.getElementsByTagName("img");
	for (var i=0; i<imgs.length; ++i) {
		if (imgs[i].className=="ibutton") {
			addEventHandler(imgs[i], "mouseover", showTip);
			addEventHandler(imgs[i], "mouseout", hideTip);
		}
	}

	initDragDrop();

	// make SelDictsDialog and load dictionaries after having read the language js
	// in callback_lang()

	// focus on the Search box
	document.getElementById("searchstr").focus();
}

window.onunload= function() {
	saveDefaultDicts();
	saveSchHistory();
}

// called when the language file has been loaded
function callback_lang() {
	//help link
	document.getElementById("help_doc").href= lang_href_help;
	//buttons
	var key;
	for (key in lang_button) {
		var elem= document.getElementById(key);
		if (elem)
			elem.value= lang_button[key];
	}
	//labels
	for (key in lang_lbl) {
		var elem= document.getElementById(key);
		if (elem)
			elem.appendChild(document.createTextNode(lang_lbl[key]));
	}

	// get the properties of all the dictionaries
	// Command: get_all_dicts
	// JSON {shortname:{
	//			dictid:..,name:..,version:..,author:..,langs:..,format:..,
	//			color:..,conv1:..,conv2:..,makeentry:..,makedef:..,
	//			schonline:..,url:..,
	//			remark:..},
	//		 ...
	//		}
	ajaxGet("/get_all_dicts", function(data) {
			Dictionaries= JSON.parse(data);
			var idx= 0;	// TODO necessary?
			for (var shortname in Dictionaries) {
				var D= Dictionaries[shortname];
				// set color
				if (D.color=="")
					D.color= bgcolors[idx];
				// string names to the actual functions
				D.conv1= DictFuncs[D.conv1];
				D.conv2= DictFuncs[D.conv2];
				D.makedef= DictFuncs[D.makedef];
				D.makeentry= DictFuncs[D.makeentry];
				if (D.schonline=="")
					D.schonline= null;
				else
					D.schonline= DictFuncs[D.schonline];
				// additional properties
				D.idx= idx++;	// TODO necessary?
				D.chk= null;
				//D.sel= false;
			}

			// Dictionary dialog
			makeSelDictsDialog();

			// the default dictionaries or show dialog
			if (DefaultDicts.length>0) {
				var i;
				// set selected
				for (i=0; i<DefaultDicts.length; ++i) {
					//Dictionaries[DefaultDicts[i]].sel= true;
					Dictionaries[DefaultDicts[i]].chk.checked= true;
				}
				showDictTitle(DefaultDicts);
			}
			else {
				showSelDictsDialog(true);
			}
		});

}

// create a dialog to select dictionaries
function makeSelDictsDialog() {
	var frag= document.createDocumentFragment();
	
	//app version
	var elem=document.createElement("div");
	elem.className="titlebar";
	elem.appendChild(document.createTextNode("Vortaroj "+version));
	frag.appendChild(elem);

	//head
	elem=document.createElement("h6");
	elem.appendChild(document.createTextNode(lang_str["dict_target"]));
	frag.appendChild(elem);

	//
	var n=0;
	for (var shortname in Dictionaries) {
		++n;
		var D= Dictionaries[shortname];

		// <div> <img-right> <label><radiobutton>dic.name<br>dic.ver</label> </div>
		elem= document.createElement("div");

		var label= document.createElement("label");
		var chkbox= document.createElement("input");
		chkbox.type="checkbox";
		chkbox.id= "chk_"+shortname;
		chkbox.name= "chk_dict";
		label.appendChild(chkbox);

		label.appendChild(document.createTextNode(n+'. '+D["name"]));
		label.appendChild(document.createElement("br"));
		var span= document.createElement("span");
		span.appendChild( document.createTextNode(D["author"]+" "+D["version"]) );
		span.style.paddingLeft="20px";
		label.appendChild(span);
		elem.appendChild(label);

		D.chk= chkbox

		frag.appendChild(elem);
	}

	frag.appendChild(document.createElement("hr"));
	//buttons
	var div= document.createElement("div");
	div.innerHTML="<input type='button' value='"+lang_str["ok"]+"' onclick='selDictsOK()'>";
	div.style.marginLeft="50px;";
	frag.appendChild(div);

	document.getElementById("seldicts").appendChild(frag);
}

//-- Title --
function showDictTitle(selDicts) {
	//img select_dicts, span dict_name
	var img= document.getElementById("select_dicts");
	var title= document.getElementById("dict_name");
	title.innerHTML= "";
	if (selDicts.length>1) {
		img.src= IMG_books;
		title.appendChild(document.createTextNode(lang_lbl.dict_name));
	} else {
		img.src= IMG_book;
		var shortname= selDicts[0];
		title.appendChild(document.createTextNode(Dictionaries[shortname].name));
	}
}

//-- Searching --

function inputSearchStr(e) {
	var evt;
	if (window.event) {
		evt= window.event;
	}
	else {
		evt= e;
	}
	var key= evt.keyCode;
	if (!key) {
		key= evt.charCode;	//for Firefox
	}

	var cancel= false;
	if (key==13) {			//[Enter] key
		search();
		cancel= true;
	}
	else if (key==40) {		//[Down] key
		showSearchHistory();
		cancel= true;
	}
	else if (key==27) {		//27 [Esc]
		setTimeout("clearSearchStr()", 100);
		cancel= true;
	}
//	else {
//		//Other char key
//		setTimeout(search, 10);
//	}

	if (cancel) {
		if (isIE()) {
			evt.returnValue=false;
			evt.cancelBubble=true;
		}
		else {
			evt.preventDefault();
			evt.stopPropagation();
		}
	}
}

// Save a word to the Search history
function addToStack(stack, item, max) {
	var i;
	for (i=0; i<stack.length; ++i) {
		if (stack[i]==item) {		//the same data exists
			stack.splice(i, 1);		// delete it
			break;
		}
	}
	stack.push(item);
	if (stack.length>max) {
		stack.shift();
	}
}

function search() {

	var selectedDicts= getSelectedDicts();
	if (selectedDicts.length==0) {
		showSelDictsDialog(true);
		showMessageBox(lang_str["msg_selectDict"]);
		return;
	}

	var schstr= document.getElementById("searchstr").value;
	schstr= schstr.replace(/^\s*(.*?)\s*$/, "$1");	//trim both
	if (schstr=="")
		return;

	addToStack(SearchHistory, schstr, defaultOpts["maxSearchHistory"]);

	// clear page buttons
	showPageButtons(0, 0);

	// Search Struct
	var r_m= document.getElementById("search_range").value.split(' ');
	var range= r_m[0];
	var match= r_m[1];

	SchRec= {'str': schstr, 'range':range,
		'match':match, //matchMode(range, schstr),
		'offset':0, 'limit':Limit, 'sort':sortOrder(),
		'currentPage':1, 'pages':1, 'nhits':0,
		'dicts':selectedDicts};

	postSchCommand(SchRec);
}

function onPageClicked(page) {
	if (page==SchRec.currentPage)
		return;

	SchRec.currentPage= page;
	SchRec.offset=(page-1)*SchRec.limit;
	postSchCommand(SchRec);
}

function postSchCommand(schrec) {
	// search: properties
	var body= "/search_props";
	body= addURLParam(body, "range", schrec.range);
	body= addURLParam(body, "match", schrec.match);
	body= addURLParam(body, "offset", schrec.offset);
	body= addURLParam(body, "limit", schrec.limit);
	body= addURLParam(body, "sort", schrec.sort);

	// search: dicts and words
	for (var n=0; n<schrec.dicts.length; ++n) {
		var shortname= schrec.dicts[n];
		var D= Dictionaries[shortname];

		// command: /search?word=..&dictid=..
		var url= "/search";
		url= addURLParam(url, "dictid", D.dictid.toString());
		var word= (schrec.range=="entiretext")? D.conv2(schrec.str): D.conv1(schrec.str);
		url= addURLParam(url, "word", word);
		body += "\n" + url;
	}

	ajaxPost("/", body, "text/plain", showResults, schrec);
}

function showResults(data, schrec) {
	var arr= JSON.parse(data);
	schrec.nhits= arr.length;
	// JSON: [[dict_shortname, word_id, word,entry_word,def], ...]
/*
	if (dicts.length>1) {
		CompStrFunc=
			(document.getElementById("sort_esp").checked)?
					compEspStr :
			(document.getElementById("sort_local").checked)?
					function(s1,s2){return s1.localeCompare(s2);} : 
					null;
		if (CompStrFunc)
			arr.sort(compWords);
	}
*/
	// Title of the list
	var schstr= schrec.str;
	var match= schrec.match;
	if (match=="prefix")
		schstr= schstr+"...";
	else if (match=="complete" || match=="word")
		;
	else if (match=="partial")
		schstr= "..."+schstr+"...";
	var hits= arr.length;
	hits= "\""+schstr+"\" "+
		((hits==1)? (hits+lang_str["hit1"]) : (hits+lang_str["hit2"]));
	var txt= document.createTextNode(hits);
	var def_hits= document.getElementById("def_hits");
	def_hits.innerHTML= "";
	def_hits.appendChild(txt);

	var btn_deleteAll= document.getElementById("lbl_deleteAll");
	var btn_toPool= document.getElementById("lbl_toPool");
	if (arr.length>0) {
		btn_deleteAll.style.display="inline";
		if (Opts.usePool)
			btn_toPool.style.display="inline";
	} else {
		btn_deleteAll.style.display="none";
		btn_toPool.style.display="none";
	}
	
	// fragments to be appended
	var frag_def= document.createDocumentFragment();

	for (n=0; n<arr.length; ++n) {
		var e= arr[n];
		var shortname= e[0];
		//var wordid= e[1];	// Note: string of number chars
		var entry= [e[2], e[3], e[4], ""];
		var D= Dictionaries[shortname];
		var div= makeDefWButton(D.makedef, entry, IMG_add, shortname);
		if (Opts.colorize)
			div.style.backgroundColor= D.color;
		frag_def.appendChild(div);
	}

	// show all
	var defs= document.getElementById("defs");
	defs.innerHTML= "";
	defs.appendChild(frag_def);
	//deleteAllDefs(defpane);
	//defpane.appendChild(div);
	//defpane.appendChild(frag_def);

	// pages
	if (schrec.nhits>=schrec.limit && schrec.currentPage==schrec.pages) {
		++schrec.pages;
	}
	if (schrec.pages>1) {
		showPageButtons(schrec.pages, schrec.currentPage);
	}

	//document.getElementById("searchstr").focus();
}

function getSelectedDicts() {
	var select=[];
	var shortname;
	for (shortname in Dictionaries) {
		var D= Dictionaries[shortname];
		if (D.chk.checked)
			select.push(shortname);
	}
	return select;
}

function listTitle(str, klass) {
	var div= document.createElement("div");
	div.className=klass;
	var txt= document.createTextNode(str);
	div.appendChild(txt);
	return div;
}

function matchMode(range, str) {
	if (range=="entries") {
		if (document.getElementById("match_prefix").checked)
			return "prefix";
		if (document.getElementById("match_complete").checked)
			return "complete";
		else
			return "partial"
	} else if (range=="entiretext") {
		if (document.getElementById("match_word_entiretext").checked)
			//&& isAllAlphabet(str))
			return "word";
		else
			return "partial";
	} else {	// range_root
		return "complete";
	}
}
/*
function toggleFindMode() {
	var img= document.getElementById("img_find_mode");
	var elem= document.getElementById("search_range");
	if (Opts.showFindMode) {
		Opts.showFindMode= false;
		img.src= IMG_FindModeX;
		elem.style.display="none";
	} else {
		Opts.showFindMode= true;
		img.src= IMG_FindMode;
		elem.style.display="inline";
	}
}
*/
// TODO: check up again and justify
function isAllAlphabet(str) {
	var i;
	for (i=0; i<str.length; ++i) {
		if (str.charAt(i)>"\u06ff")		//latin, greek, cyril, hebrew, arabian, etc.
			return false;
	}
	return true;
//	return /^[a-z ĉĝĥĵŝŭ]+$/.test(str);
}

function sortOrder() {
	return "esperanto";	//TODO
/*	if (document.getElementById("sort_esp").checked)
		return "esperanto";
	else if (document.getElementById("sort_local").checked)
		return "local";	// TODO
	else
		return "none";
*/
}

// entry1/2: [dict_shortname, word_id, word,entry_word,def,aux]
function compWords(entry1, entry2) {
	return CompStrFunc(entry1[2].toLowerCase(), entry2[2].toLowerCase());
}

function compEspStr(s1,s2) {
	var table={	'ĉ':'cx', 'ĝ':'gx', 'ĥ':'hx', 'ĵ':'jx', 'ŝ':'sx', 'ŭ':'ux'};
	for (var i=0; ;++i) {
		var s1end= i>=s1.length;
		var s2end= i>=s2.length;
		if (s1end && s2end)
			return 0;
		else if (s1end)
			return -1;
		else if (s2end)
			return 1;
		else {
			var c1= s1.charAt(i);
			var c2= s2.charAt(i);
			if (table[c1])
				c1= table[c1];
			if (table[c2])
				c2= table[c2];
			if (c1<c2)
				return -1;
			else if (c1>c2)
				return 1;
		}
	}
}

//---------------------------
// POOL
//---------------------------
function getPool() {
	var pool= document.getElementById("pool");
	var content= document.getElementById("poolContent");
	var img= document.getElementById("img_pool");
//	if (show!=undefined) {
//		img.src= IMG_open;
//		pool.style.display= (show)? "block":"none";
//		if (show)
//			content.style.display="block";
//	}
	return {'pool':pool, 'content':content, 'img':img};
//	return [pool, content, img];
}

function togglePool() {
	var img= document.getElementById("img_use_pool");
	if (Opts.usePool) {
		Opts.usePool= false;
		img.src= IMG_PoolX;
		usePool(false);
	} else {
		Opts.usePool= true;
		img.src= IMG_Pool;
		usePool(true);
	}
}

function usePool(use) {
	var p= getPool();
	var btn_toPool= document.getElementById("lbl_toPool");
	var btn_emptyPool= document.getElementById("lbl_emptyPool");
	var hasDefs= document.getElementById("defs").childNodes.length > 0;
	var poolFilled= document.getElementById("poolContent").childNodes.length > 0;
	if (use) {
		p.img.src= IMG_open;
		p.content.style.display= "block";
		p.pool.style.display= "block";
		btn_toPool.style.display= hasDefs? "inline":"none";
		btn_emptyPool.style.display= poolFilled? "inline":"none";
	} else {
		p.pool.style.display= "none";
		btn_toPool.style.display= "none";
	}
}

function moveToPool(entryDiv) {
	entryDiv.firstChild.src= IMG_remove;
	var pool= getPool();
	pool.content.appendChild(entryDiv);	//move to Pool
	document.getElementById("lbl_emptyPool").style.display="inline";
}

function moveAllToPool() {
	var pool= getPool();
	var frag= document.createDocumentFragment();
	var ch= document.getElementById("defs").firstChild;
	while (ch) {
		var nextCh= ch.nextSibling;
		ch.firstChild.src= IMG_remove;
		frag.appendChild(ch);
		ch= nextCh;
	}
	pool.content.appendChild(frag);
	document.getElementById("lbl_emptyPool").style.display="inline";
}

function emptyPool() {
	var pool= getPool();
	pool.content.innerHTML= "";
	document.getElementById("lbl_emptyPool").style.display="none";
}

function removeFromPool(div) {
	var pool= getPool();
	pool.content.removeChild(div);
}

function foldPool() {
	var pool= getPool();
	if (pool.img.src.indexOf(IMG_open)>=0) {
		pool.content.style.display="none";
		pool.img.src= IMG_closed;
	}
	else {
		pool.content.style.display="block";
		pool.img.src= IMG_open;
	}
}

//---------------------------
// Conv
//---------------------------

function no_conv(str) {
	return str.toLowerCase();
}

// x notation to diacritical chars
function chapeligu(str) {
	var table={	'c':'ĉ', 'g':'ĝ', 'h':'ĥ', 'j':'ĵ', 's':'ŝ', 'u':'ŭ',
				'C':'Ĉ', 'G':'Ĝ', 'H':'Ĥ', 'J':'Ĵ', 'S':'Ŝ', 'U':'Ŭ'};
	var str1= str.toLowerCase();
	var outstr="";
	for (var i=0; i<str1.length; ++i) {
		var c= str1.charAt(i);
		if (c=='x' || c== 'X') {
			var len= outstr.length;
			var prev= (len>0)? outstr.charAt(len-1) : '';
			var cc= table[prev];
			if (cc) {
				outstr= outstr.substring(0, len-1) + cc;
			}
			else {
				outstr += c;
			}
		}
		else {
			outstr += c;
		}
	}
	return outstr;
}

// japanese long signs to vowels
function longToVowel(str) {
	var tbls= [
		"あかさたなはまやらわがざだばぱぁゃ",
		"いきしちにひみりぎじぢびぴぃ",
		"うくすつぬふむゆるぐずづぶぷぅゅ",
		"えけせてねへめれげぜでべぺぇ",
		"おこそとのほもよろごぞどぼぽぉょ"];
	var vowels= "あいうえお";

	var outstr= "";
	var i, j;
	for (i=0; i<str.length; ++i) {
		var c= str.charAt(i);
		if (c=='ー' || c=='－') {
			var c0= (i>0)? str.charAt(i-1) : '　';
			for (j=0; j<5; ++j) {
				if (tbls[j].indexOf(c0)>=0) {
					c= vowels[j];
					break;
				}
			}
		}
		outstr += c;
	}
	return outstr;
}

//
var hiragana= {
	a:"あ", i:"い", u:"う", e:"え", o:"お",
	ka:"か", ki:"き", ku:"く", ke:"け", ko:"こ",
	ga:"が", gi:"ぎ", gu:"ぐ", ge:"げ", go:"ご",
	sa:"さ", si:"し", su:"す", se:"せ", so:"そ",
	za:"ざ", zi:"じ", zu:"ず", ze:"ぜ", zo:"ぞ",
	ta:"た", ti:"ち", tu:"つ", te:"て", to:"と",
	da:"だ", di:"ぢ", du:"づ", de:"で", "do":"ど",
	na:"な", ni:"に", nu:"ぬ", ne:"ね", no:"の",
	ha:"は", hi:"ひ", hu:"ふ", he:"へ", ho:"ほ",
	ba:"ば", bi:"び", bu:"ぶ", be:"べ", bo:"ぼ",
	pa:"ぱ", pi:"ぴ", pu:"ぷ", pe:"ぺ", po:"ぽ",
	ma:"ま", mi:"み", mu:"む", me:"め", mo:"も",
	ya:"や", yu:"ゆ", yo:"よ",
	ra:"ら", ri:"り", ru:"る", re:"れ", ro:"ろ",
	wa:"わ", wo:"を",
	n:"ん",

	kya:"きゃ", kyu:"きゅ", kye:"きぇ", kyo:"きょ",
	gya:"ぎゃ", gyu:"ぎゅ", gye:"ぎぇ", gyo:"ぎょ",
	sya:"しゃ", syu:"しゅ", sye:"しぇ", syo:"しょ",
	zya:"じゃ", zyu:"じゅ", zye:"じぇ", zyo:"じょ",
	tya:"ちゃ", tyu:"ちゅ", tye:"ちぇ", tyo:"ちょ",
	dya:"ぢゃ", dyu:"ぢゅ", dye:"ぢぇ", dyo:"ぢょ",
	nya:"にゃ", nyu:"にゅ", nye:"にぇ", nyo:"にょ",
	hya:"ひゃ", hyu:"ひゅ", hye:"ひぇ", hyo:"ひょ",
	bya:"びゃ", byu:"びゅ", bye:"びぇ", byo:"びょ",
	pya:"ぴゃ", pyu:"ぴゅ", pye:"ぴぇ", pyo:"ぴょ",
	mya:"みゃ", myu:"みゅ", mye:"みぇ", myo:"みょ",
	rya:"りゃ", ryu:"りゅ", rye:"りぇ", ryo:"りょ",

	sha:"しゃ", shi:"し", shu:"しゅ", she:"しぇ", sho:"しょ",
	ja:"じゃ", ji:"じ", ju:"じゅ", je:"じぇ", jo:"じょ",
	cha:"ちゃ", chi:"ち", chu:"ちゅ", che:"ちぇ", cho:"ちょ",
	dja:"ぢゃ", dji:"ぢ", dju:"ぢゅ", dje:"ぢぇ", djo:"ぢょ",
	tsa:"つぁ", tsi:"つぃ", tsu:"つ", tse:"つぇ", tso:"つぉ",
	dza:"づぁ", dzi:"づぃ", dzu:"づ", dze:"づぇ", dzo:"づぉ",
	dsa:"づぁ", dsi:"づぃ", dsu:"づ", dse:"づぇ", dso:"づぉ",
	fa:"ふぁ", fi:"ふぃ", fu:"ふ", fe:"ふぇ", fo:"ふぉ",
	thi:"てぃ", thu:"とぅ", dhi:"でぃ", dhu:"どぅ",
	la:"ぁ", li:"ぃ", lu:"ぅ", le:"ぇ", lo:"ぉ",
	lya:"ゃ", lyu:"ゅ", lyo:"ょ",
};

//Japanese romanized spelling to Hiragana
function romajiToHiragana(str) {
	var str1= str.toLowerCase();
	var outstr= "";
	var i= 0;
	while (i<str1.length) {
		var syl= "";	//syllable
		var nxt= "";
		while (i<str1.length) {
			var c= str1.charAt(i);
			++i;
			if (c.charCodeAt(0)>=128) {	//possibly hiragana
				outstr += c;
				//syl= "";
			}
			else if (/[aiueo]/.test(c)) {
				syl += c;
				break;
			}
			else if (/[a-z]/.test(c)) {
				syl += c;
			}
			else if (/[ '-]/.test(c)) {	//delimiter
				break;
			}
			else {
				nxt= c;					//other ASCII chars
				break;
			}
		}
		if (syl) {
			var kana= hiragana[syl];
			if (kana)
				outstr += kana;
			else {
				var cons= syl.charAt(0);
				if (cons=='n' || cons=='m')
					outstr += "ん";
				else
					outstr += "っ";
				syl= syl.substring(1);
				kana= hiragana[syl];
				if (kana)
					outstr += kana;
			}
		}
		if (nxt)
			outstr += nxt;
	}

	return outstr;
}

function romaji_kana(schstr) {
	return longToVowel(romajiToHiragana(schstr));
}

//---------------------------
// Make 'DIV' for Entry/Def
//---------------------------

// One Entry in the entry-list
//klass: "k"=header, "r"=entry item,"g"=entry item(grey)
//index : index of the entry
function makeEntry_std(entry, params, klass) {
	var div= document.createElement("div");
	div.className=klass;
	div.setAttribute("params", params);
	var txt= document.createTextNode((entry[1])?entry[1]:entry[0]);
	div.appendChild(txt);
	return div;
}

// butler
function makeEntry_std2(entry, index, klass) {
	var word= ((entry[1])?entry[1]:entry[0]).replace('-','');
	var div= document.createElement("div");
	div.className=klass;
	div.setAttribute("params", index);
	var txt= document.createTextNode(word);
	div.appendChild(txt);
	return div;
}

// create one definition-entry
//entry [0]reading [1]entry word [2]definitions
function makeDef_plain(entry) {
	var div=document.createElement("div");
	div.className= "def";
	var h=document.createElement("span");
	h.innerHTML= "<b>"+((entry[1])? entry[1]:entry[0])+"</b>&nbsp; &nbsp; ";
	var d=document.createTextNode(entry[2]);
	div.appendChild(h);
	div.appendChild(d);
	return div;
}

function makeDef_plain2(entry) {
	var div=document.createElement("div");
	div.className= "def";
	var h=document.createElement("span");
	h.innerHTML= "<b>"+entry[1]+" ("+entry[0]+")</b>&nbsp; &nbsp; ";
	var d=document.createTextNode(entry[2]);
	div.appendChild(h);
	div.appendChild(d);
	return div;
}

function makeDef_html(entry) {
	var div=document.createElement("div");
	div.className= "def";
	var h=document.createElement("span");
	h.innerHTML= "<b>"+((entry[1])? entry[1]:entry[0])+"</b>&nbsp; &nbsp; ";
	div.innerHTML= entry[2];
	div.insertBefore(h, div.firstChild);
	return div;
}

//<div params=... style=...>
//  <img (xbutton)>
//  <span><b>word</b>  </span>
//  ..html_def..
//</div>
function makeDefWButton(makeDef, entry, button, dictName) {
	var div= makeDef(entry);
	div.setAttribute("params", dictName);
	var img= document.createElement("img");
	img.src= button;
	img.className="xbutton";
	div.firstChild.style.marginLeft="5px";
	div.insertBefore(img, div.firstChild);
	return div;
}

function toggleColorize() {
	var img= document.getElementById("img_colorize");
	if (Opts.colorize) {
		Opts.colorize= false;
		img.src= IMG_ColorizeX;
		colorize(false);
	} else {
		Opts.colorize= true;
		img.src= IMG_Colorize;
		colorize(true);
	}
}

function colorize(on) {
	//var list= document.getElementById("results");
	var pool= document.getElementById("poolContent");
	var defs= document.getElementById("defs");
	colorizeEach(pool, defs, (on)? getColor : function(ch){return '';})
}
function colorizeEach(pool, defs, color) {
/*	var ch= list.firstChild;
	while (ch) {
		if (ch.nodeName=='DIV' && ch.className=='r') {
			ch.style.backgroundColor= color(ch);
		}
		ch= ch.nextSibling;
	}
*/
	// pool
	var ch= pool.firstChild;
	while (ch) {
		if (ch.nodeName=='DIV') {
			ch.style.backgroundColor= color(ch);
		}
		ch= ch.nextSibling;
	}
	// defs
	ch= defs.firstChild;
	while (ch) {
		if (ch.nodeName=='DIV' && !ch.id) {
			ch.style.backgroundColor= color(ch);
		}
		ch= ch.nextSibling;
	}
}
function getColor(div) {
	var attr= div.getAttribute('params');
	if (!attr)
		return '';	// the top [div], showing 'match count'
	var params= attr.split(' ');
	return Dictionaries[params[0]].color;
}

function onDefClicked(evt) {
	var target;
	if (window.event) {
		evt= window.event;
		target= evt.srcElement;
	}
	else
		target= evt.target;

	if (target.className=="xbutton") {
		var elem= target.parentNode;
		if (Opts.usePool) {
			if (target.src.indexOf(IMG_add)>=0) {			// (+)
				moveToPool(elem);
			}
			else if (target.src.indexOf(IMG_remove)>=0) {	// (-)
				removeFromPool(elem);
			}
		}
	}
	else if (target.nodeName=="A") {
		if (target.href.indexOf("vorto:")==0) {
			var def_div= target.parentNode;
			var shortname= def_div.getAttribute("params");
			var D= Dictionaries[shortname];
			var vorto= target.href.substring(6); //"vorto:VORTO"; NB VORTO is URI-encoded!
			// query : /search?dictid=xx&word=xxx
			// return: [dict_shortname, word_id, word,entry_word,def]
			var url= "/search?dictid="+D["dictid"]+"&word="+vorto.toLowerCase();
			ajaxGet(url, function(data) {
				var jsn= JSON.parse(data);
				if (jsn.length>0) {
					var imgsrc= def_div.firstChild.src;
					var entry= [jsn[2], jsn[3], jsn[4], ""];
					var div= makeDefWButton(D.makedef, entry, imgsrc, shortname);
					if (Opts.colorize)
						div.style.backgroundColor= Dictionaries[shortname].color;
					def_div.parentNode.replaceChild(div, def_div);
				}
			});
			// cancel the propagation
			if (isIE()) {
				evt.returnValue= false;
				evt.cancelBubble= true;
			} else {
				evt.preventDefault();
				evt.stopPropagation();
			}
		}
//		else {
//			allow event
//		}
	}
	else if (target.nodeName=='B') {
		// tricky !
		var shortname= target.parentNode.parentNode.getAttribute("params");
		if (shortname)
			showDictNameTip(shortname, evt, 1500);
	}
	// focus on the search box
	//document.getElementById("searchstr").focus();
}

function showDictNameTip(dicID, evt, msec) {
	var dicname= Dictionaries[dicID]["name"];

	clearTimeout(o_tiptimer);
	var elem=document.getElementById("tip");
	elem.style.left= (evt.clientX+15)+"px";
	elem.style.top= (evt.clientY)+"px";
	elem.innerHTML= dicname;
	elem.style.display="inline";

	o_tiptimer= setTimeout("hideTip()", msec);
}

function showDictName(evt) {
	var target;
	if (window.event) {
		evt= window.event;
		target= evt.srcElement;
	}
	else
		target= evt.target;

	if (target.className=='dict_n') {
		showDictNameTip(target.getAttribute('params'), evt, 3000);
	}
}

//--- Page buttons ---

// set max=0, to clear the page buttons
function showPageButtons(max, cur) {
	document.getElementById("lbl_page").style.display= (max<=1)? "none" : "inline";
	for (i=1; i<=MaxPages; ++i) {
		var e= document.getElementById("page"+i);
		if (i<=max) {
			e.className= (i==cur)? "pageC" : "pageA";
		} else {
			e.className="pageN";
		}
	}
}

//---------------------------
// History
//---------------------------
// clicked on [History] button
function showSearchHistory() {
	var sel= document.getElementById("selectSchHistory");
	sel.size= SearchHistory.length;

	if (sel.style.display=="none") {
		//SHOW
		sel.innerHTML="";
		var frag= document.createDocumentFragment();
		var i;
		for (i=SearchHistory.length-1; i>=0; --i) {
			var opt= document.createElement("option");
			opt.appendChild(document.createTextNode(SearchHistory[i]));
			frag.appendChild(opt);
		}
		sel.appendChild(frag);
		var rect= document.getElementById("searchstr").getBoundingClientRect();
		sel.style.top= rect.bottom+"px";
		sel.style.left= (rect.left-5)+"px";
		sel.style.display="block";
		sel.focus();
		//setTimeout(function(){sel.style.display="block";}, 50);
	}
	else {
		//HIDE
		sel.style.display="none";
		//document.getElementById("searchstr").focus();
	}
}
function schHistoryKeyPress(e) {
	var evt;
	if (window.event) {
		evt= window.event;
	}
	else {
		evt= e;
	}
	var key= evt.keyCode;
	if (!key) {
		key= evt.charCode;	//for Firefox
	}

	var cancel= false;
	if (key==13) {			//[Enter]
		onSearchHistory(e);
		cancel= true;
	}
	else if (key==27) {		//[ESC]
		showSearchHistory();
		cancel= true;
	}

	if (cancel) {
		if (isIE()) {
			evt.returnValue=false;
			evt.cancelBubble=true;
		}
		else {
			evt.preventDefault();
			evt.stopPropagation();
		}
	}
}
// clicked in the list of Search History
function onSearchHistory(evt) {
	var inpElem= document.getElementById("searchstr");
	var sel= document.getElementById("selectSchHistory");
	var ch= sel.firstChild;		//<option>
	while (ch) {
		if (ch.selected) {
			inpElem.value= getText(ch);
			search();
			break;
		}
		ch= ch.nextSibling;
	}
	sel.style.display="none";
	//inpElem.focus();
}

// clicked on [Clear] button
function clearSearchStr() {
	var elem= document.getElementById("searchstr");
	elem.value="";
	//elem.focus();
}

//---------------------------
// dictionary dialog
//---------------------------

// show/hide the sel.dicts dialog
function showSelDictsDialog(show) {
	var elem= document.getElementById("seldicts");
//	if (show==undefined)
//		show= elem.style.display=="none";	//toggle
	if (show) {
		// SHOW
		elem.style.display= "block";
	}
	else {
		// HIDE
		elem.style.display= "none";
	}
	//document.getElementById("searchstr").focus();
}
function selDictsOK() {
	var select= [];
	var shortname;
	for (shortname in Dictionaries) {
		var d= Dictionaries[shortname];
		//selected
		if (d.chk.checked) {
			select.push(shortname);
		}
	}
	// check to see if dictionaries selected
	if (select.length==0) {
		showMessageBox(lang_str["msg_selectDict"]);
		return;
	}

	saveDefaultDicts();

	//initialize the title
	showDictTitle(select);

	// hide the dialog
	var elem= document.getElementById("seldicts");
	elem.style.display= "none";

	//document.getElementById("searchstr").focus();
}

///////////////////////////////////

//--- read/save cookie ---

function saveSchHistory() {
	var schHistory= SearchHistory.join(',');
	saveCookie("schHistory", schHistory);
}
function saveDefaultDicts() {
	var dicts= "";
	for (var shortname in Dictionaries) {
		var D= Dictionaries[shortname];
		if (!D.chk.checked)
			continue;
		// selected dict.
		if (dicts.length==0)
			dicts= shortname;
		else
			dicts += ","+shortname;
	}
	saveCookie("defaultDicts", dicts);
}

// https://so-zou.jp/web-app/tech/programming/javascript/cookie/
function saveCookie(name, val) {
	var maxage= (30*24*60*60).toString();	//30days in [sec]
	var cookie= name+"="+encodeURIComponent(val)+"; max-age="+maxage+"; path='/'";
	document.cookie= cookie;
}
function getCookie() {
	var result= {'defaultDicts':[], 'schHistory':[]};
	var cookie= document.cookie;
	if (cookie) {
		var cs= cookie.split(/;\s*/);
		for (var i=0; i<cs.length; ++i) {
			var nv= cs[i].split("=");
			var name= nv[0];
			var val= decodeURIComponent(nv[1]);
			result[name]= val.split(",");
		}
	}
	return result;
}

//--- erase the display ---

function deleteAllDefs() {
	showPageButtons(0, 0);
	document.getElementById("defs").innerHTML= "";
	var def_hits= document.getElementById("def_hits");
	def_hits.removeChild(def_hits.firstChild);
	def_hits.appendChild(document.createTextNode("★"));
	//
	document.getElementById("lbl_deleteAll").style.display="none";
	document.getElementById("lbl_toPool").style.display="none";
}

//--- Option Dialog ---

// page: 0:hide, 1,2,3:show the page, -1:show the current page
function showOptionDialog(page) {
	//var pages=["searchOpts", "dispOpts", "otherOpts"];	//page ID
	var pages=["dispOpts", "otherOpts"];	//page ID

	var dialog= document.getElementById("optionDialog");
	if (page==0) {
		dialog.style.display="none";
		//document.getElementById("searchstr").focus();
	} else if (page<0) {
		dialog.style.display="block";
		//document.getElementById("searchstr").focus();
	} else {
		var i;
		for (i=1; i<=pages.length; ++i) {
			var tab= document.getElementById("tab"+i);
			var div= document.getElementById(pages[i-1]);
			if (i==page) {
				tab.style.color= "black";
				div.style.display="block";
			}
			else {
				tab.style.color= "grey";
				div.style.display="none";
			}
		}
		dialog.style.display="block";
	}
}

// TODO not used
function onShowDefSettings() {
	var elem= document.getElementById("dispOpts");
	if (elem.style.display=="none") {
		elem.style.display="block";
	}
	else {
		elem.style.display="none";
		//document.getElementById("searchstr").focus();
	}
}

// TODO not used
function showSearchOpts() {
	var elem= document.getElementById("searchOpts");
	if (elem.style.display=="none") {
		elem.style.display="block";
	}
	else {
		elem.style.display="none";
		//document.getElementById("searchstr").focus();
	}
}

//--- Miscellaneous ---

// highlighted selection
function getSel() {
	var sel= (window.getSelection)? window.getSelection():document.selection;
	return sel;
}
function getRange() {
	var sel= getSel();
	var rng= (sel.rangeCount>0)? sel.getRangeAt(0): sel.createRange();
	return rng;
}

function getText(elem) {
	var ch=elem.firstChild;
	while (ch) {
		if (ch.nodeType==3)
			return ch.nodeValue;
		ch=ch.nextSibling;
	}
	return "";
}
function getText_nest(elem) {
	//NB: NodeIterator doesn't work for <A>, why?
	var text= "";
	var ch= elem.firstChild;
	while (ch) {
		if (ch.nodeType==3)			//text
			text += ch.nodeValue;
		else if (ch.nodeType==1)	//element
			text += getText(ch);
		ch= ch.nextSibling;
	}
	return text;
}

//--- Mouse ---
// dragging
var dragging= null;
function initDragDrop() {
	document.onmousedown= onMouseDown;
	document.onmouseup= onMouseUp;
}
function onMouseDown(evt) {
	if (!evt)
		evt= window.event;
	var target= (evt.target)? evt.target : evt.srcElement;
	//left click: IE=1, Firefox=0
	//Mouse buttons
	// Click->	L	M	R
	// firefox	0	1	2
	// IE		1	4	2
	if (isIE() && evt.button==1 || evt.button==0) {
		var className= target.className;
		var elem, x, y;
		if (className=='titlebar') {
			target= target.parentNode;	//dialog!
			elem= target;
			x= parseInt(target.style.left);
			y= parseInt(target.style.top);
		}
		/*
		else if (className=='vsash') {
			elem= [
				document.getElementById("results"),
				target,
				document.getElementById("defpane")
				];
			x= parseInt(target.style.left);
			y= parseInt(target.style.top);
		}
		*/
		else {
			return;
		}
		dragging= {
			drag: className,
			elem: elem,
			startX: evt.clientX,
			startY: evt.clientY,
			offsetX: x,
			offsetY: y,
		};
		document.onmousemove= onMouseMove;
		document.body.focus();	//cancel out any text slections
		document.onselectstart= function(){return false;};	//prevent text selection in IE
		document.ondragstart= function(){return false;};	//prevent IE from trying to drag an image
		return false;	//prevent text selection (except IE)
	}
/*
	else if (evt.button==2) {
		//right button
		var rng= getRange();
		if (!rng.collapsed) {
			//-- with selection
			var frag= rng.cloneContents();
			var text= getText_nest(frag);
			// TODO
			var elem=document.getElementById("tip");
			elem.style.left= (evt.clientX)+"px";
			elem.style.top= (evt.clientY+20)+"px";
			elem.innerHTML= text;
			elem.style.display="inline";

			setTimeout("document.getElementById('tip').style.display='none'", 1000);
		}
	}
*/
}

function onMouseMove(evt) {
	if (!evt)
		evt= window.event;
	var x= dragging.offsetX+evt.clientX-dragging.startX;
	var y= dragging.offsetY+evt.clientY-dragging.startY;
	if (dragging.drag=='titlebar' && x>=0 && y>=0) {
		dragging.elem.style.left= x + 'px';
		dragging.elem.style.top= y + 'px';
	}
	else if (dragging.drag=='vsash' && x>=30) {
		dragging.elem[0].style.width= (x-5) + 'px';
		dragging.elem[1].style.left= x + 'px';
		dragging.elem[2].style.left= (x+5) + 'px';
	}
}
function onMouseUp(evt) {
	if (dragging) {
		document.onmousemove= null;
		document.onselectstart= null;
		document.ondragstart= null;
		dragging= null;
	}
}

//--- Tips and Messages---

var o_tiptimer;
function showTip() {
	var evt;
	if (window.event)
		evt=window.event;
	else
		evt=arguments[0];

	var targetId= (isIE()? evt.srcElement: evt.target).id;
	var tip= lang_tips[targetId];
	if (tip) {
		clearTimeout(o_tiptimer);
		var elem=document.getElementById("tip");
		elem.style.left= (evt.clientX+15)+"px";
		elem.style.top= (evt.clientY)+"px";
		elem.innerHTML= tip;
		elem.style.display="inline";
		o_tiptimer= setTimeout("hideTip()", 1100);
	}
}
function hideTip() {
	clearTimeout(o_tiptimer);
	document.getElementById("tip").style.display="none";
}

// message box
var o_msgtimer;
var o_msgtimecount;

function showMessageBox(msg) {
	var msgtext= document.getElementById("msgtext");
	msgtext.innerHTML=msg;
	var elem= document.getElementById("messagebox");
	elem.style.opacity="1.0";
	elem.style.filter="alpha(opacity=100)";
	elem.style.display="block";
	o_msgtimecount=50;
	o_msgtimer= setTimeout("blurMsgbox()", 100);
}
function closeMessageBox() {
	document.getElementById("messagebox").style.display="none";
	clearTimeout(o_msgtimer);
}
function blurMsgbox() {
	--o_msgtimecount;
	if (o_msgtimecount==0) {
		closeMessageBox();
		return;
	}
	else if (o_msgtimecount<=25) {
		var elem=document.getElementById("messagebox");
		elem.style.opacity=(o_msgtimecount/25.0);
		var n= 100*o_msgtimecount/25;
		elem.style.filter="alpha(opacity="+n+")";
	}
	o_msgtimer= setTimeout("blurMsgbox()", 100);
}

// FOR TEST
function onQuit() {
	var ret= ajaxGet("/quit");
	if (confirm("Close the window? (y/n)"))
		window.open('about:blank','_self').close();
}

