window.onload = function() {
	loadGraph();

	for (var id in {help: 0, search: 0, filter: 0, log: 0, sectioning: 0}) restoreState(id);

	window.onkeydown = taste;

	$('#txtcmd').focus().select();

	// draggables
	$('.box').draggable({handle: '.handle', stack: '.box', stop: saveState});
	// draggables on top when clicked
	$('.box').on('mouseup', function(){
		var $box = $(this);
		if(!$box.hasClass('ui-draggable-dragging')){
			var zIndexList = $('.box').map(function(){return $(this).zIndex()}).get();
			var highestZIndex = Math.max.apply(null, zIndexList);
			if($box.zIndex() < highestZIndex){
				$box.zIndex(highestZIndex + 1);
				saveState();
			}
		}
	});
	// resizables
	$('#help').resizable({handles: 'all', minHeight: 45, minWidth: 120, stop: saveState});
	$('#search').resizable({handles: 'all', minHeight: 141, minWidth: 310, stop: saveState});
	$('#filter').resizable({handles: 'all', minHeight: 131, minWidth: 220, stop: saveState});
	$('#log').resizable({handles: 'all', minHeight: 90, minWidth: 400, stop: saveState});
	$('#sectioning').resizable({handles: 'all', minHeight: 45, minWidth: 50, stop: saveState});

	// function of close button
	$('.handle').html('<div class="close"></div>')
	$(document).on('click', '.close', function(){
		$(this).closest('.box').hide();
		saveState();
		$('#txtcmd').focus().select();
	});

	// behaviour of file settings modal
	$(document).on('click', '.file #save-log', function(){
		if ($('.file #save-log').is(':checked'))
			$('.file #separate-log').removeAttr('disabled');
		else
			$('.file #separate-log').attr('disabled', '');
	});
}
window.onresize = graphdivEinpassen;

function loadGraph() {
	$.ajax({
		url: '/draw_graph',
		dataType: 'json'
	}).done(updateView);
}
function graphdivEinpassen() {
	$('#graph').height(window.innerHeight - $('#bottom').height());
}
function graphEinpassen() {
	var $div = $('#graph');
	var $svg = $div.find('svg');
	var outerHeight = $div.height() - 20;
	var newHeight = Math.min(outerHeight, $svg.height());
	$svg.width($svg.width() / $svg.height() * newHeight);
	$svg.height(newHeight);
	$svg.css('top', outerHeight - $svg.height());
}
function taste(e) {
	var ctrlShift = e.ctrlKey && e.shiftKey;
	if (ctrlShift) {
		switch (e.which) {
			case  33: verschiebeBild('oo'); e.preventDefault(); break;
			case  34: verschiebeBild('uu'); e.preventDefault(); break;
			case  35: verschiebeBild('e'); e.preventDefault(); break;
			case  36: verschiebeBild('a'); e.preventDefault(); break;
			case  37: verschiebeBild('l'); e.preventDefault(); break;
			case  38: verschiebeBild('o'); e.preventDefault(); break;
			case  39: verschiebeBild('r'); e.preventDefault(); break;
			case  40: verschiebeBild('u'); e.preventDefault(); break;
			case 173:
			case 189:
			case 109: aendereBildgroesze('-'); e.preventDefault(); break;
			case 171:
			case 187:
			case 107: aendereBildgroesze('+'); e.preventDefault(); break;
			case  48: graphEinpassen(); e.preventDefault(); break;
		}
	}
	else if (e.altKey) {
		var mapping = {
			37: 'prev',
			39: 'next',
			36: 'first',
			35: 'last',
		};
		var mapping2 = {
			38: 'up',
			40: 'down'
		};
		if (e.which in mapping) {
			e.preventDefault();
			Sectioning.navigateSentences(mapping[e.which]);
		} else if (e.which in mapping2) {
			e.preventDefault();
			toggleAndSave('#sectioning', true)
			Sectioning.selection(mapping2[e.which]);
		}
	}
	else {
		var mapping = {
			112: function(){
				toggleAndSave('#help')
			},
			113: function(){
				var textline = document.getElementById('textline');
				var meta = document.getElementById('meta');
				if (textline.style.display != 'none') {
					if (meta.style.display != 'none' || meta.innerHTML == '') {
						textline.style.display = 'none';
						meta.style.display = 'none';
					} else {
						meta.style.display = 'block';
					}
				} else {
					textline.style.display = 'block';
					if (meta.innerHTML != '') meta.style.display = 'none'; else meta.style.display = 'block';
				}
				graphdivEinpassen();
			},
			115: function(){
				$.getJSON('/toggle_refs').done(updateView);
			},
			117: function(){
				toggleAndSave('#filter');
				if ($('#filter').css('display') == 'none') {
					$('#txtcmd').focus().select();
				} else {
					$('#filterfield').focus();
				}
			},
			118: function(){
				toggleAndSave('#search');
				if ($('#search').css('display') == 'none') {
					$('#txtcmd').focus().select();
				} else {
					$('#query').focus();
				}
			},
			119: function(){
				toggleAndSave('#log');
			},
			120: function(){
				toggleAndSave('#sectioning');
			},
		};
		if (e.which in mapping) {
			e.preventDefault();
			mapping[e.which]();
		}
	}
}
function aendereBildgroesze(richtung) {
	var $div = $('#graph');
	var $svg = $div.find('svg');
	var xmitte = $div.scrollLeft() + $div.width() / 2;
	var ymitte = $div.scrollTop() + $div.height() / 2;
	var faktor = 1;
	if (richtung == '+') {faktor = 1.25}
	else if (richtung == '-') {faktor = 0.8}
	$svg.width($svg.width() * faktor);
	$svg.height($svg.height() * faktor);
	$div.scrollLeft(xmitte * faktor - $div.width() / 2);
	$div.scrollTop(ymitte * faktor - $div.height() / 2);
	tieToBottom($svg, $div);
}
function verschiebeBild(richtung) {
	var div = document.getElementById('graph');
	switch (richtung) {
		case 'oo': div.scrollTop = 0; break;
		case 'uu': div.scrollTop = 999999; break;
		case 'a': div.scrollLeft = 0; break;
		case 'e': div.scrollLeft = 999999; break;
		case 'l': div.scrollLeft -= 50; break;
		case 'o': div.scrollTop  -= 50; break;
		case 'r': div.scrollLeft += 50; break;
		case 'u': div.scrollTop  += 50; break;
	}
}
function updateView(data) {
	data = data || {};
	if (data['textline'] != undefined) $('#textline').html(data['textline']);
	if (data['meta'] != undefined) $('#meta').html(data['meta']);
	if (data['sections'] != undefined) Sectioning.setList(data['sections']);
	if (data['current_sections'] != undefined) Sectioning.setCurrent(data['current_sections']);
	graphdivEinpassen();
	// get old dimensions
	var $div = $('#graph');
	var oldImageSize = {
		width: $div.find('svg').width() || 1,
		height: $div.find('svg').height() || 1,
	};
	if (window.originalSvgSize == undefined) originalSvgSize = oldImageSize;
	// create svg
	try {
		var svgElement = new DOMParser().parseFromString(Viz(data['dot'], 'svg'), 'image/svg+xml');
	} catch(e) {
		alert('An error occurred while generating the graph. Try the xlabel setting for avoiding this (see file settings window)');
		return;
	}
	// get new dimensions
	var newSvgSize = {
		width: parseInt(svgElement.documentElement.getAttribute('width')),
		height: parseInt(svgElement.documentElement.getAttribute('height')),
	};
	// insert svg
	$div.empty().append(svgElement.documentElement);
	var $svg = $div.find('svg');
	// scale svg
	if (data['sections_changed']) {
		$svg.width(newSvgSize.width);
		$svg.height(newSvgSize.height);
		graphEinpassen();
	} else {
		$svg.width(newSvgSize.width * oldImageSize.width / originalSvgSize.width);
		$svg.height(newSvgSize.height * oldImageSize.height / originalSvgSize.height);
		if ($div.scrollTop() == 0) tieToBottom($svg, $div);
	}
	originalSvgSize = newSvgSize;
}
function tieToBottom($svg, $div) {
	$svg.css('top', Math.max(($div.height()-20) - $svg.height(), 0));
}
function sendCmd() {
	var txtcmd = document.cmd.txtcmd.value.trim();
	if (txtcmd.indexOf('image ') == 0) {
		saveImage(txtcmd.replace(/\s+/g, ' ').split(' ')[1]);
		return;
	}
	postRequest('/handle_commandline', {
		txtcmd: txtcmd,
		layer: document.cmd.layer.value,
		sections: Sectioning.getCurrent(),
	});
}
function saveImage(format) {
	var width = parseInt($('#graph svg').attr('width'));
	var height = parseInt($('#graph svg').attr('height'));
	var url = 'data:image/svg+xml;base64,' +
		window.btoa(unescape(encodeURIComponent(
			[
				'<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
				'<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">',
				$('#graph').html(),
			].join("\n")
		)));
	if (format == 'svg') {
		downloadFile(url, format);
	} else if (format == 'png') {
		var image = new Image();
		image.src = url;
		image.onload = function() {
			if (window.canvas == undefined) canvas = document.createElement('canvas');
			canvas.width = width;
			canvas.height = height;
			canvas.getContext('2d').drawImage(image, 0, 0, width, height);
			downloadFile(canvas.toDataURL('image/png'), format);
		}
		return;
	}
}
function downloadFile(url, format) {
	var link = $('<a></a>').appendTo($('body'));
	link.attr('href', url).attr('download', 'image.' + format)
		.css('display', 'none')
		.get(0).click();
	link.remove();
}
function sendFilter(mode) {
	postRequest('/filter', {filter: document.filter.filterfield.value, mode: mode});
	$('#filter input').removeClass('selected_filter_mode');
	document.getElementById(mode).className = 'selected_filter_mode';
}
function sendSearch() {
	postRequest('/search', {query: document.search.query.value});
}
function clearSearch() {
	postRequest('/clear_search', {});
}
function sendDataExport() {
	$.post(
		'/export_data',
		{query: document.search.query.value}
	).done(function(data){
		if (data == '') location = "/export_data_table/data_table.csv";
		else display_search_message(data);
	});
}
function sendAnnotateQuery() {
	postRequest('/annotate_query', {query: document.search.query.value});
}
function setSelectedIndex(s, v) {
	for (var i = 0; i < s.options.length; i++) {
		if (s.options[i].value == v) {
			s.options[i].selected = true;
			return;
		}
	}
}
function getCookie(name) {
	var nameEQ = name + "=";
	var ca = document.cookie.split(';');
	for(var i = 0; i < ca.length; i++) {
		var c = ca[i];
		while (c.charAt(0) == ' ') c = c.substring(1, c.length);
		if (c.indexOf(nameEQ) == 0) return decodeURIComponent(c.substring(nameEQ.length, c.length).replace(/\+/g, ' '));
	}
	return null;
}
function postRequest(path, params) {
	$.post(path, params, null, 'json')
	.done(function(data) {
		switch (data['modal']) {
			case undefined:
				break;
			case 'import':
				openImport(data['type']);
				return;
			default:
				openModal(data['modal']);
				return;
		}
		var txtcmd = document.getElementById('txtcmd');
		txtcmd.value = getCookie('traw_cmd');
		updateLayerOptions();
		for (var id in data['windows']) {
			restoreState(id, data['windows']);
		};
		saveState();
		if (data['messages'] != undefined && data['messages'].length > 0) alert(data['messages'].join("\n"));
		if (data['command'] == 'load') Log.load();
		if (data['graph_file'] != undefined) $('#active_file').html('file: ' + data['graph_file']);
		if (data['current_annotator'] != undefined) $('#current_annotator').html('annotator: ' + data['current_annotator']);
		if (data['search_result'] != undefined) {
			display_search_message(data['search_result']);
		} else if (data['filter_applied'] != undefined) {
			filterfield.focus();
		} else {
			txtcmd.focus();
			txtcmd.select();
		}
		updateView(data);
		Log.update();
	});
}
function newLayer(element) {
	var number = parseInt($(element).closest('tbody').prev().attr('no')) + 1;
	$.get('/new_layer/' + number)
	.done(function(data){
		$('#new-layer').closest('tbody').before(data);
		$('label[for^="combinations["][for$="[attr]]"]').closest('td').next().each(function(i){
			$(this).append("<input name='combinations["+i+"[attr["+number+"]]]' type='checkbox' value=''>\n<label for='combinations["+i+"[attr["+number+"]]]'></label>\n<br>");
		});
	});
}
function newCombination(element) {
	var number = parseInt($(element).closest('tbody').prev().attr('no')) + 1;
	$.get('/new_combination/' + number)
	.done(function(data) {
		$('#new-combination').closest('tbody').before(data);
		removeLayerAttributes();
		$('input[name^="layers["][name$="[attr]]"]').each(function(i){
		  setLayerAttributes(this);
		});
	});
}
function removeLayer(element) {
	$(element).closest('tbody').remove();
	removeLayerAttributes();
}
function openModal(type) {
	if ($('#modal-background').css('display') != 'block') {
		$('#modal-content').load('/' + type + '_form', function(){
			$('#modal-background').show();
			window.onkeydown = configKeys;
		});
	}
}
function newFormSegment(partial, selector) {
	var i = parseInt($(selector + ' tbody:first-child tr:last-child').attr('no')) + 1;
	$.get('/new_form_segment/' + i, {partial: partial})
	.done(function(data) {
		$(selector + ' tbody:first-child tr:last-child').after(data);
	});
}
function removeElement(selector, element) {
	$(element).closest(selector).remove();
}
function sendConfig() {
	$.ajax({
		type: 'POST',
		url: '/save_config',
		dataType: 'json',
		data: $('#modal-form').serialize()
	})
	.done(function(data) {
		if (data == true) {
			closeModal();
			updateLayerOptions();
			loadGraph();
		} else {
			$('#modal-warning').show();
			$('#modal-form label').removeClass('error_message');
			for (var i in data) {
				$('label[for="' + i + '"]').addClass('error_message');
			}
		}
	});
}
function sendModal(type) {
	$.ajax({
		type: 'POST',
		url: '/save_' + type,
		dataType: 'json',
		data: $('#modal-form').serialize()
	})
	.done(function(data) {
		if (data == true) closeModal();
		else $('#modal-warning').html(data['errors']).show();
	});
}
function closeModal() {
	$('#modal-background').hide();
	$('#txtcmd').focus();
	window.onkeydown = taste;
}
function updateLayerOptions() {
	$('#layer').load('/layer_options', function(){
		setSelectedIndex(document.getElementById('layer'), getCookie('traw_layer'));
	});
}
function configKeys(e) {
	if (e.which == 27 || e.which == 119) {
		e.preventDefault();
		closeModal();
	}
}
function setLayerAttributes(field) {
	var number = field.name.match(/layers\[(\d+)/)[1];
	var value = field.value;
	$('input[name^="combinations["][name$="[attr[' + number + ']]]"]').attr('value', value).next().html(value);
}
function removeLayerAttributes(number) {
	$('table.combinations tbody').each(function() {
		$(this).find('input[name*="[attr["]').each(function() {
			var number = this.name.match(/attr\[(\d+)/)[1];
			if($('table.layers tbody[no='+number+']').length == 0) {
				$(this).next().remove();
				$(this).next().remove();
				$(this).remove();
			}
		});
	});
}
function openImport(type) {
	$('#modal-content').load('/import_form/' + type, function(){
		disable_import_form_fields(type);
		$('#modal-background').show();
		window.onkeydown = importKeys;
	});
}
function importKeys(e) {
	if (e.which == 27) {
		e.preventDefault();
		closeModal();
	}
}
function sendImport(type) {
	var formData = new FormData($('#modal-form')[0]);
	$.ajax({
		url: '/import/' + type,
		type: 'POST',
		data: formData,
		dataType: 'json',
		//Options to tell jQuery not to process data or worry about content-type.
		cache: false,
		contentType: false,
		processData: false
	})
	.done(function(data) {
		if (data['sections'] != undefined) {
			closeModal();
			updateLayerOptions();
			loadGraph();
			$('#active_file').html('file:');
		}
		if (data['current_annotator'] != undefined) $('#current_annotator').html('annotator: ' + data['current_annotator']);
	})
	.error(function(data) {
		alert('An error occurred while importing.');
	});
}
function disable_import_form_fields(type) {
	if(type == 'toolbox') return;
	if($('input[value="file"]').is(':checked')){
		$('textarea[name="paste"]').attr('disabled', true);
		$('input[name="file"]').removeAttr('disabled');
	} else {
		$('input[name="file"]').attr('disabled', true);
		$('textarea[name="paste"]').removeAttr('disabled');
	}
	if($('input[value="regex"]').is(':checked')){
		$('input[name="language"]').attr('disabled', true);
		$('input[name^="sentences"], input[name^="tokens"]').removeAttr('disabled');
	} else {
		$('input[name^="sentences"], input[name^="tokens"]').attr('disabled', true);
		$('input[name="language"]').removeAttr('disabled');
	}
}
function display_search_message(message) {
	$('#searchresult').html(message);
	query.focus();
}
function toggleAndSave(selector, state) {
	$(selector).toggle(state);
	saveState();
}
function saveState() {
	var data = {};
	$('.box').each(function(){
		var $box = $(this);
		var key = $box.attr('id');
		data[key] = {};
		for (var attr in {display: 0, left: 0, top: 0, width: 0, height: 0, 'z-index': 0}) {
			data[key][attr] = $box.css(attr);
		}
		document.cookie = key + '=' + JSON.stringify(data[key]) + '; expires=Fri, 31 Dec 9999 23:59:59 GMT';
	});
	$.post('/save_window_positions', {data: data});
}
function restoreState(id, data) {
	var $element = $('#' + id);
	if (data == undefined) var attributes = JSON.parse(getCookie(id));
	else var attributes = data[id];
	for (var i in attributes) {
		$element.css(i, attributes[i]);
	}
}
