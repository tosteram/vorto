/*
File	init.js
Date	2014-06-28, 07-16; v2.0 08-01; v2.1 2016-03-06
		v3.0 2018-01-13

Copyright (C) 2014-2018, Tositaka TERAMOTO & FUKUMOTO Hirotsugu.
Permission to use, copy, modify, and distribute this software and 
its documentation for any purpose (including commercial) is hereby granted 
without fee, provided that the above copyright notice appear in all 
copies and that both that copyright notice and this permission 
notice appear in supporting documentation.
This file is provided "as is" without express or implied warranty.
*/

var version="v3.0 (2018-01-13)";
var available_langs= ["eo","en","ja"];
var lang_file= null;	//"lang_XX.js";


/////////////////////////////
// Options
var defaultOpts= {
	//search options
	maxSearchHistory:20,
	searchRange:"entries prefix",
	showFindMode:true,			//true, false
	usePool:false,				//true, false
	colorize: false,			//true, false

	//others
	font_family:"Tahoma, Times New Roman, sans-serif",
	font_size:"12pt",
//	sort: "sort_esp",			//"sort_none", "sort_esp", "sort_local"
};

/////////////////////////////
// Background colours
var bgcolors= [
	"#F5FFB1", "#D8FFB1", "#BAFFB1", "#B1FFC4", "#CDFEEC",
	"#C1D4FF", "#E6CDFE", "#FFF1E9", "#F8FECD", "#FCE9FF",
	"#E6E6E6", "#E8FABE", "#FAF4DB", "#DAF5EE", "#DFDAF5",
	"#F6E9F4", "#F3F6E9", "#DDFFE3", "#FAFFDD", "#FFEDDD",
	];

