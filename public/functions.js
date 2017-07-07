// Copyright © 2014-2017 Lennart Bierkandt <post@lennartbierkandt.de>
//
// This file is part of GraphAnno.
//
// GraphAnno is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// GraphAnno is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with GraphAnno. If not, see <http://www.gnu.org/licenses/>.

window.onload = function() {
	loadGraph();

	window.onkeydown = taste;

	// commandline
	$('#txtcmd').closest('form').on('submit', function(e){
		e.preventDefault();
		Autocomplete.disable();
		sendCmd();
	});
	$('#txtcmd').on('blur', function(e){
		Autocomplete.disable();
	})

	// behaviour of file settings modal
	$(document).on('change', '.file #save-log', function(){
		disableInputs($(this), '.file #separate-log');
	});

	// behaviour of preferences modal
	$(document).on('change', '.pref #autocompletion', function(){
		disableInputs($(this), 'input.autocompletion');
	});
	$(document).on('change', '.pref #autosave', function(){
		disableInputs($(this), 'input.autosave');
	});

	// autocomplete
	Autocomplete.init('#txtcmd');
}

function loadGraph() {
	$.ajax({
		url: '/draw_graph',
		dataType: 'json'
	}).done(handleResponse);
}
function taste(e) {
	var ctrlShift = e.ctrlKey && e.shiftKey;
	if (ctrlShift) {
		switch (e.which) {
			case  33: GraphDisplay.moveGraph('oo'); e.preventDefault(); break;
			case  34: GraphDisplay.moveGraph('uu'); e.preventDefault(); break;
			case  35: GraphDisplay.moveGraph('e'); e.preventDefault(); break;
			case  36: GraphDisplay.moveGraph('a'); e.preventDefault(); break;
			case  37: GraphDisplay.moveGraph('l'); e.preventDefault(); break;
			case  38: GraphDisplay.moveGraph('o'); e.preventDefault(); break;
			case  39: GraphDisplay.moveGraph('r'); e.preventDefault(); break;
			case  40: GraphDisplay.moveGraph('u'); e.preventDefault(); break;
			case 173:
			case 189:
			case 109: GraphDisplay.scaleGraph('-'); e.preventDefault(); break;
			case 171:
			case 187:
			case 107: GraphDisplay.scaleGraph('+'); e.preventDefault(); break;
			case  48: GraphDisplay.fitGraph(); e.preventDefault(); break;
		}
	}
	else if (e.altKey && e.shiftKey) {
		switch (e.which) {
			case  80: GraphDisplay.jumpToFragment('prev'); e.preventDefault(); break;
			case  78: GraphDisplay.jumpToFragment('next'); e.preventDefault(); break;
		}
	}
	else if (e.altKey) {
		var mapping = {
			37: 'prev',
			39: 'next',
			36: 'first',
			35: 'last',
			80: 'prevMatch',
			78: 'nextMatch',
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
			Box.instances.sectioning.toggleAndSave(true);
			Sectioning.selection(mapping2[e.which]);
		}
	}
	else if (e.ctrlKey) {
		var mapping = {
			121: function(){
				Box.instances.media.toggleAndSave();
			},
		}
		if (e.which in mapping) {
			e.preventDefault();
			mapping[e.which]();
		}
	}
	else {
		var mapping = {
			112: function(){
				Box.instances.help.toggleAndSave();
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
				GraphDisplay.fitGraphdiv();
			},
			115: function(){
				$.getJSON('/toggle_refs').done(handleResponse);
			},
			117: function(){
				Box.instances.filter.toggleAndSave();
				if ($('#filter').css('display') == 'none') focusCommandLine();
				else focusFilterField;
			},
			118: function(){
				Box.instances.search.toggleAndSave();
				if ($('#search').css('display') == 'none') focusCommandLine();
				else focusSearchField();
			},
			119: function(){
				Box.instances.log.toggleAndSave();
			},
			120: function(){
				Box.instances.sectioning.toggleAndSave();
			},
			121: function(){
				Box.instances.independent.toggleAndSave();
			},
		};
		if (e.which in mapping) {
			e.preventDefault();
			mapping[e.which]();
		}
	}
}
function sendCmd() {
	var txtcmd = document.cmd.txtcmd.value.trim();
	if (txtcmd.indexOf('image ') == 0) {
		GraphDisplay.saveImage(txtcmd.replace(/\s+/g, ' ').split(' ')[1]);
		return;
	}
	postRequest('/handle_commandline', {
		txtcmd: txtcmd,
		layer: document.cmd.layer.value,
		sections: Sectioning.getCurrent(),
	});
}
function sendFilter(mode) {
	postRequest('/set_filter', {filter: document.filter.filterfield.value, mode: mode}, focusFilterField);
	$('#filter input').removeClass('selected_filter_mode');
	document.getElementById(mode).className = 'selected_filter_mode';
}
function sendSearch() {
	postRequest('/search', {query: document.search.query.value}, focusSearchField);
}
function sendAnnotateQuery() {
	postRequest('/annotate_query', {query: document.search.query.value}, focusSearchField);
}
function clearSearch() {
	postRequest('/clear_search', {}, focusSearchField);
}
function sendDataExport() {
	$.post(
		'/export_data',
		{query: document.search.query.value}
	).done(function(data){
		if (data == '') location = "/export_data_table/data_table.csv";
		else {$('#searchresult').html(data); focusSearchField();}
	});
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
function disableInputs($master, selector) {
	if ($master.is(':checked'))
		$(selector).removeAttr('disabled');
	else
		$(selector).attr('disabled', '');
}
function postRequest(path, params, callback, silent) {
	$.post(path, params, null, 'json')
	.done(function(data) {
		switch (data.modal) {
			case undefined:
				break;
			case 'import':
				openImport(data.type);
				return;
			default:
				openModal(data.modal);
				return;
		}
		if (silent) {callback(); return};
		$('#txtcmd').val(getCookie('traw_cmd'));
		handleResponse(data);
		Log.update();
		if (callback) callback();
		else focusCommandLine();
	});
}
function newLayer(element) {
	var number = parseInt($(element).closest('tbody').prev().attr('no')) + 1;
	$.get('/new_layer/' + number)
	.done(function(data){
		$('#new-layer').closest('tbody').before(data);
		$('label[for^="combinations["][for$="[layers]]"]').closest('td').next().each(function(i){
			$(this).append("<input name='combinations["+i+"[layers["+number+"]]]' type='checkbox' value=''>\n<label for='combinations["+i+"[layers["+number+"]]]'></label>\n<br>");
		});
	});
}
function newCombination(element) {
	var number = parseInt($(element).closest('tbody').prev().attr('no')) + 1;
	$.get('/new_combination/' + number)
	.done(function(data) {
		$('#new-combination').closest('tbody').before(data);
		removeLayerAttributes();
		$('input[name^="layers["][name$="[shortcut]]"]').each(function(i){
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
		if (data.preferences != undefined) setPreferences(data.preferences);
		if (!data || data.errors != undefined) $('#modal-warning').html(data.errors).show();
		else {
			Autocomplete.setData(data.autocomplete);
			closeModal();
		}
	});
}
function closeModal() {
	$('#modal-background').hide();
	focusCommandLine();
	window.onkeydown = taste;
}
function configKeys(e) {
	if (e.which == 27 || e.which == 119) {
		e.preventDefault();
		closeModal();
	}
}
function setLayerAttributes(field) {
	var number = field.name.match(/^layers\[(\d+)/)[1];
	var value = field.value;
	$('input[name^="combinations["][name$="[layers[' + number + ']]]"]').attr('value', value).next().html(value);
}
function removeLayerAttributes(number) {
	$('table.combinations tbody').each(function() {
		$(this).find('input[name*="[layers["]').each(function() {
			var number = this.name.match(/layers\[(\d+)/)[1];
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
		if (data.sections != undefined) {
			closeModal();
			loadGraph();
			$('#active_file').html('file:');
		}
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
function setMedia(media) {
	if (media === undefined) return;
	var $video = $('#media video');
	if (media === null) $video.removeAttr('src').load();
	else $video.removeAttr('src').attr('src', 'media?' + new Date().getTime());
}
function playMedia(data) {
	var $video = $('#media video');
	if (data.start != undefined) $video[0].currentTime = data.start;
	if (data.end != undefined) $video.on('timeupdate', function(){
		if (this.currentTime >= data.end) {
			$(this).off('timeupdate');
			this.pause();
		}
	});
	$video[0].play();
}
function setPreferences(pref) {
	window.preferences = pref;
	$('#button-bar').toggle(preferences.button_bar);
	if (window.autosaveInterval) clearInterval(autosaveInterval);
	if (preferences.autosave) {
		autosaveInterval = setInterval(function(){
			$alert = $('<span class="alert">saving...</span>');
			$('#active_file').append($alert);
			postRequest('/handle_commandline', {txtcmd: 'save'}, function(){
				$alert.detach();
			}, true);
		}, preferences.autosave_interval * 60 * 1000);
	}
}
function focusCommandLine() {
	$('#txtcmd').focus().select();
}
function focusSearchField() {
	$('#query').focus();
}
function focusFilterField() {
	$('#filterfield').focus()
}
function handleResponse(data) {
	$('#layer').load('/layer_options', function(){
		setSelectedIndex(document.getElementById('layer'), getCookie('traw_layer'));
	});
	if (data.windows != undefined) {
		for (var id in data.windows) Box.instances[id].restoreState(data.windows);
		Box.saveState();
	}
	if (data.messages != undefined && data.messages.length > 0) alert(data.messages.join("\n"));
	if (data.command == 'load') Log.load();
	if (data.command == 'play') playMedia(data);
	if (data.graph_file != undefined) $('#active_file').html('file: ' + data.graph_file);
	if (data.current_annotator != undefined) $('#current_annotator').html('annotator: ' + data.current_annotator);
	if (data.textline != undefined) $('#textline').html(data.textline);
	if (data.meta != undefined) $('#meta').html(data.meta);
	if (data.i_nodes != undefined) $('#independent .content').html(data.i_nodes);
	if (data.sections != undefined) Sectioning.setList(data.sections);
	if (data.update_sections != undefined) Sectioning.updateList(data.update_sections);
	if (data.current_sections != undefined) Sectioning.setCurrent(data.current_sections);
	if (data.preferences != undefined) setPreferences(data.preferences);
	if (data.search_result != undefined) $('#searchresult').html(data.search_result);
	if (data.found_fragments != undefined) GraphDisplay.setFoundFragments(data.found_fragments);
	setMedia(data.media);
	Autocomplete.setData(data.autocomplete);
	GraphDisplay.updateView(data);
}
