window.onload = function() {
	loadGraph();

	for (var id in {search: 0, filter: 0, log: 0, sectioning: 0}) restoreState(id);

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
		async: false,
		dataType: 'json'
	}).done(updateView);
}
function graphdivEinpassen() {
	$('#graphdiv').height(window.innerHeight - $('#bottom').height());
}
function graphEinpassen() {
	var bild = document.getElementById('graph');
	var outerHeight = document.getElementById('graphdiv').offsetHeight - 20;
	var newHeight = Math.min(outerHeight, bild.svgHeight);
	bild.height = Math.round(newHeight);
	bild.width = Math.round(bild.svgWidth / bild.svgHeight * newHeight);
	bild.style.top = outerHeight - bild.height;
}
function taste(tast) {
	var ctrlShift = tast.ctrlKey && tast.shiftKey;
	if (ctrlShift) {
		switch (tast.which) {
			case  33: verschiebeBild('oo'); tast.preventDefault(); break;
			case  34: verschiebeBild('uu'); tast.preventDefault(); break;
			case  35: verschiebeBild('e'); tast.preventDefault(); break;
			case  36: verschiebeBild('a'); tast.preventDefault(); break;
			case  37: verschiebeBild('l'); tast.preventDefault(); break;
			case  38: verschiebeBild('o'); tast.preventDefault(); break;
			case  39: verschiebeBild('r'); tast.preventDefault(); break;
			case  40: verschiebeBild('u'); tast.preventDefault(); break;
			case 173:
			case 189:
			case 109: aendereBildgroesze('-'); tast.preventDefault(); break;
			case 171:
			case 187:
			case 107: aendereBildgroesze('+'); tast.preventDefault(); break;
			case  48: graphEinpassen(); tast.preventDefault(); break;
		}
	}
	else if (tast.altKey) {
		var mapping = {
			37: 'prev',
			39: 'next',
			36: 'first',
			35: 'last',
		};
		if (tast.which in mapping) {
			tast.preventDefault();
			Sectioning.navigateSentences(mapping[tast.which]);
		}
	}
	else {
		var mapping = {
			112: function(){
				$('#help').toggle();
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
				$('#filter').toggle();
				saveState();
				if ($('#filter').css('display') == 'none') {
					$('#txtcmd').focus().select();
				} else {
					$('#filterfield').focus();
				}
			},
			118: function(){
				$('#search').toggle();
				saveState();
				if ($('#search').css('display') == 'none') {
					$('#txtcmd').focus().select();
				} else {
					$('#query').focus();
				}
			},
			119: function(){
				$('#log').toggle();
				saveState();
			},
			120: function(){
				$('#sectioning').toggle();
				saveState();
			},
			121: function(){
				openModal('tagset');
			},
		};
		if (tast.which in mapping) {
			tast.preventDefault();
			mapping[tast.which]();
		}
	}
}
function aendereBildgroesze(richtung) {
	var bild = document.getElementById('graph');
	var div = document.getElementById('graphdiv');
	var xmitte = div.scrollLeft + div.offsetWidth / 2
	var ymitte = div.scrollTop + div.offsetHeight / 2
	var faktor = 1;
	if (richtung == '+') {faktor = 1.25}
	else if (richtung == '-') {faktor = 0.8}
	bild.width  *= faktor;
	bild.height *= faktor;
	div.scrollLeft = xmitte * faktor - div.offsetWidth / 2;
	div.scrollTop  = ymitte * faktor - div.offsetHeight / 2;
	bild.style.top = Math.max((div.offsetHeight-20) - bild.height, 0);
}
function verschiebeBild(richtung) {
	var div = document.getElementById('graphdiv');
	switch (richtung) {
		case 'oo': div.scrollTop = 0; break;
		case 'uu': div.scrollTop = 9999; break;
		case 'a': div.scrollLeft = 0; break;
		case 'e': div.scrollLeft = 9999; break;
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
	var bild = document.getElementById('graph');
	var scrollLeft = bild.parentNode.scrollLeft;
	var scrollTop  = bild.parentNode.scrollTop;
	bild.onload = function(){
		var svgElement = this.contentDocument.documentElement;
		var newSvgWidth  = svgElement.getAttribute('width').match(/\d+/);
		var newSvgHeight = svgElement.getAttribute('height').match(/\d+/);
		var widthRatio = newSvgWidth  / this.svgWidth;
		var heightRatio  = newSvgHeight / this.svgHeight;
		this.svgWidth  = newSvgWidth;
		this.svgHeight = newSvgHeight;
		if (data['sections_changed']) {
			graphEinpassen();
		} else {
			this.width  = this.width  * widthRatio;
			this.height = this.height * heightRatio;
			this.parentNode.scrollLeft = scrollLeft * widthRatio;
			this.parentNode.scrollTop  = scrollTop  * heightRatio;
			// Graphik ggf. "am Boden" halten:
			if (scrollTop == 0) {
				var outerHeight = document.getElementById('graphdiv').offsetHeight - 20;
				this.style.top = Math.max(outerHeight - this.height, 0);
			}
		}
	}
	bild.data = '/graph.svg?v=' + new Date().getTime();
}
function sendCmd() {
	postRequest('/handle_commandline', {
		txtcmd: document.cmd.txtcmd.value,
		layer: document.cmd.layer.value,
	});
}
function sendFilter(mode) {
	postRequest('/filter', {filter: document.filter.filterfield.value, mode: mode});

	document.getElementById('hide rest').className = '';
	document.getElementById('hide selected').className = '';
	document.getElementById('filter rest').className = '';
	document.getElementById('filter selected').className = '';
	document.getElementById('display all').className = '';
	document.getElementById(mode).className = 'selected_filter_mode';
	//filter.style.display = 'none';
	//$('#txtcmd').focus().select();
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
	$.post(
		path,
		params,
		null,
		'json'
	).done(function(data) {
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
		if (data['command'] == 'load') reloadLogTable();
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
		updateLogTable();
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
function removeCombination(element) {
	$(element).closest('tbody').remove();
}
function openModal(type) {
	if ($('#modal-background').css('display') != 'block') {
		$.get('/' + type + '_form')
		.done(function(data) {
			$('#modal-content').html(data);
			$('#modal-background').show();
			window.onkeydown = configKeys;
		});
	}
}
function newMetadata() {
	var i = parseInt($('.metadata tbody:first-child tr:last-child').attr('no')) + 1;
	$('.metadata tbody:first-child tr:last-child').after(
		'<tr no="'+i+'"><td><input name="keys['+i+']" type="text"></td><td><textarea name="values['+i+']"></textarea></td></tr>'
	);
}
function newSpeaker() {
	var i = parseInt($('.speakers tbody:first-child tr:last-child').attr('no')) + 1;
	$('.speakers tbody:first-child tr:last-child').after(
		'<tr no="'+i+'"><td><input type="hidden" name="ids['+i+']"></input></td><td><textarea name="attributes['+i+']"></textarea></td></tr>'
	);
}
function newAnnotator() {
	var i = parseInt($('.annotators tbody:first-child tr:last-child').attr('no')) + 1;
	$.get('/new_annotator/' + i)
	.done(function(data) {
		$('.annotators tbody:first-child tr:last-child').after(data);
	});
}
function removeAnnotator(element) {
	$(element).closest('tr').remove();
}
function newMakro() {
	var i = parseInt($('.makros tbody:first-child tr:last-child').attr('no')) + 1;
	$('.makros tbody:first-child tr:last-child').after(
		'<tr no="'+i+'"><td><input name="keys['+i+']" type="text"></td><td><input name="values['+i+']" type="text"></td></tr>'
	);
}
function newTagsetRule() {
	var i = parseInt($('.tagset tbody:first-child tr:last-child').attr('no')) + 1;
	$('.tagset tbody:first-child tr:last-child').after(
		'<tr no="'+i+'"><td><input name="keys['+i+']" type="text"></td><td><textarea name="values['+i+']"></textarea></td></tr>'
	);
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
			if (data['makros'] != 'undefined') {
				$('label[for="makros"]').html(data['makros']);
			}
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
		else $('#modal-warning').show();
	});
}
function closeModal() {
	$('#modal-background').hide();
	$('#txtcmd').focus();
	window.onkeydown = taste;
}
function updateLayerOptions() {
	$.get('/layer_options')
	.done(function(data) {
		$('#layer').html(data);
		setSelectedIndex(document.getElementById('layer'), getCookie('traw_layer'));
	});
}
function configKeys(tast) {
	if (tast.which == 27 || tast.which == 119) {
		tast.preventDefault();
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
	$.get('/import_form/' + type)
	.done(function(data) {
		$('#modal-content').html(data);
		disable_import_form_fields(type);
		$('#modal-background').show();
		window.onkeydown = importKeys;
	});
}
function importKeys(tast) {
	if (tast.which == 27) {
		tast.preventDefault();
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
function goToStep(i) {
	$.post('/go_to_step/' + i, {sentence: Sectioning.getCurrent()}, null, 'json')
	.done(function(data){
		updateLogTable();
		updateView(data);
	});
}
function updateLogTable() {
	$.getJSON('/get_log_update')
	.done(function(data){
		if (data['current_index'] == data['max_index']) {
			var currentStep = $('#log table tr[index="'+data['current_index']+'"]');
			if (currentStep.length == 0) {
				$('#log .content table').append(data['html']);
			} else {
				currentStep.replaceWith(data['html']);
			}
		}
		$('#log table tr[index]').each(function(){
			var index = $(this).attr('index');
			if (index > data['max_index']) $(this).remove();
			else if (index > data['current_index']) $(this).addClass('undone');
			else $(this).removeClass('undone') ;
		});
	});
}
function reloadLogTable() {
	$.get('/get_log_table')
	.done(function(data){
		$('#log .content').html(data);
	});
}
function saveState() {
	var data = {};
	$('.box').each(function(){
		var $box = $(this);
		var key = $box.attr('id');
		data[key] = {};
		var attributes = ['display', 'left', 'top', 'width', 'height', 'z-index'];
		for (var i = 0; i < attributes.length; i++) {
			data[key][attributes[i]] = $box.css(attributes[i]);
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
