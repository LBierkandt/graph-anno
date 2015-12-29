window.onload = function() {
	loadGraph();

	window.onkeydown = taste;
	// $('#sentence').change(changeSentence);

	$('#txtcmd').focus().select();

	$('.box').draggable({handle: '.handle', stack: '.box'});
	$('#search').resizable({handles: 'all', minHeight: 141, minWidth: 310});
	$('#filter').resizable({handles: 'all', minHeight: 131, minWidth: 220});
	$('#log').resizable({handles: 'all', minHeight: 90, minWidth: 400});

	$('.handle').html('<div class="close"></div>')
	$(document).on('click', '.close', function(){
		$(this).closest('.box').hide();
		$('#txtcmd').focus().select();
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
	var graphdiv = document.getElementById('graphdiv');
	var bottom   = document.getElementById('bottom');
	graphdiv.style.height = window.innerHeight - bottom.offsetHeight;
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
	else if (tast.which == 112) {
		tast.preventDefault();
		$('#help').toggle();
	}
	else if (tast.which == 113) {
		tast.preventDefault();
		var textline = document.getElementById('textline');
		var meta = document.getElementById('meta');
		if (textline.style.display != 'none') {
			if (meta.style.display != 'none' || meta.innerHTML == '') {
				textline.style.display = 'none';
				meta.style.display = 'none';
			}
			else {
				meta.style.display = 'block';
			}
		}
		else {
			textline.style.display = 'block';
			if (meta.innerHTML != '') meta.style.display = 'none'; else meta.style.display = 'block';
		}
		graphdivEinpassen();
	}
	else if (tast.which == 115) {
		tast.preventDefault();
		$.ajax({
			url: '/toggle_refs',
			dataType: 'json'
		}).done(updateView);
	}
	else if (tast.which == 117) {
		tast.preventDefault();
		$('#filter').toggle();
		if ($('#filter').css('display') == 'none') {
			$('#txtcmd').focus().select();
		}
		else {
			$('#filterfield').focus();
		}
	}
	else if (tast.which == 118) {
		tast.preventDefault();
		$('#search').toggle();
		if ($('#search').css('display') == 'none') {
			$('#txtcmd').focus().select();
		}
		else {
			$('#query').focus();
		}
	}
	else if (tast.which == 119) {
		tast.preventDefault();
		$('#log').toggle();
	}
	else if (tast.which == 120) {
		tast.preventDefault();
		openModal('metadata');
	}
	else if (tast.which == 121) {
		tast.preventDefault();
		openModal('tagset');
	}
	else if (tast.altKey && tast.which == 37) {
		tast.preventDefault();
		navigateSentences('prev');
	}
	else if (tast.altKey && tast.which == 39) {
		tast.preventDefault();
		navigateSentences('next');
	}
	else if (tast.altKey && tast.which == 36) {
		tast.preventDefault();
		navigateSentences('first');
	}
	else if (tast.altKey && tast.which == 35) {
		tast.preventDefault();
		navigateSentences('last');
	}
}
function navigateSentences(target) {
		var sentenceField = document.getElementById('sentence');
		switch(target) {
			case 'first': sentenceField.selectedIndex = 0; break;
			case 'prev': sentenceField.selectedIndex = Math.max(sentenceField.selectedIndex - 1, 0); break;
			case 'next':
				var lastSelected = 0;
				for(var i = 0; i < sentenceField.options.length; i++) {
					if (sentenceField.options[i].selected) lastSelected = i;
				}
				sentenceField.selectedIndex = Math.min(lastSelected + 1, sentenceField.options.length - 1);
				break;
			case 'last': sentenceField.selectedIndex = sentenceField.options.length - 1; break;
		}
		changeSentence();
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
function updateView(antworthash) {
	antworthash = antworthash || {};
	if (antworthash['textline'] != undefined) $('#textline').html(antworthash['textline']);
	if (antworthash['meta'] != undefined) $('#meta').html(antworthash['meta']);
	if (antworthash['sentence_list'] != undefined) build_sentence_list(antworthash['sentence_list']);
	$('#sentence').val(getCookie('traw_sentence').split('&'));
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
		if (antworthash['sentence_changed']) {
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
function sendCmd(txtcmd) {
	if (txtcmd == undefined) txtcmd = document.cmd.txtcmd.value;
	var layer = document.cmd.layer.value;
	var sentence = $('#sentence').val();
	var anfrage = new XMLHttpRequest();
	var params = 'txtcmd='+encodeURIComponent(txtcmd)+'&layer='+encodeURIComponent(layer)+'&sentence='+encodeURIComponent(sentence);
	anfrage.open('POST', '/handle_commandline');
	makeAnfrage(anfrage, params);
}
function sendFilter(mode) {
	var filterfield = document.filter.filterfield.value;
	var anfrage = new XMLHttpRequest();
	var params = 'filter=' + encodeURIComponent(filterfield) + '&mode=' + encodeURIComponent(mode);
	anfrage.open('POST', '/filter');
	makeAnfrage(anfrage, params);

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
	var query = document.search.query.value;
	var anfrage = new XMLHttpRequest();
	var params = 'query=' + encodeURIComponent(query);
	anfrage.open('POST', '/search');
	makeAnfrage(anfrage, params);
}
function clearSearch() {
	var anfrage = new XMLHttpRequest();
	var params = '';
	anfrage.open('POST', '/clear_search');
	makeAnfrage(anfrage, params);
}
function sendDataExport() {
	var query = document.search.query.value;
	var anfrage = new XMLHttpRequest();
	var params = 'query=' + encodeURIComponent(query);
	anfrage.open('POST', '/export_data');
	anfrage.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
	anfrage.onreadystatechange = function () {
		if (anfrage.readyState == 4 && anfrage.status == 200) {
			if (anfrage.responseText == '') {
				location = "/export_data_table/data_table.csv";
			} else {
				display_search_message(anfrage.responseText);
			}
		}
	}
	anfrage.send(params);
}
function sendAnnotateQuery() {
	var query = document.search.query.value;
	var anfrage = new XMLHttpRequest();
	var params = 'query=' + encodeURIComponent(query);
	anfrage.open('POST', '/annotate_query');
	makeAnfrage(anfrage, params);
}
function setSelectedIndex(s, v) {
	for ( var i = 0; i < s.options.length; i++ ) {
		if ( s.options[i].value == v ) {
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
function makeAnfrage(anfrage, params) {
		anfrage.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
		anfrage.onreadystatechange = function() {
			if (this.readyState == 4 && this.status == 200) {
				var antworthash = JSON.parse(this.responseText);
				switch (antworthash['modal']) {
					case undefined:
						break;
					case 'import':
						openImport(antworthash['type']);
						return;
					default:
						openModal(antworthash['modal']);
						return;
				}
				var txtcmd = document.getElementById('txtcmd');
				txtcmd.value = getCookie('traw_cmd');
				updateLayerOptions();
				if (antworthash['messages'] != undefined && antworthash['messages'].length > 0) alert(antworthash['messages'].join("\n"));
				if (antworthash['command'] == 'load') reloadLogTable();
				if (antworthash['graph_file'] != undefined) $('#active_file').html('file: ' + antworthash['graph_file']);
				if (antworthash['current_annotator'] != undefined) $('#current_annotator').html('annotator: ' + antworthash['current_annotator']);
				if (antworthash['search_result'] != undefined) {
					display_search_message(antworthash['search_result']);
				} else if (antworthash['filter_applied'] != undefined) {
					filterfield.focus();
				} else {
					txtcmd.focus();
					txtcmd.select();
				}
				updateView(antworthash);
				updateLogTable();
			}
		}
		anfrage.send(params);
}
function changeSentence() {
	var txtcmd = document.cmd.txtcmd.value;
	var layer = document.cmd.layer.value;
	var sentence = document.cmd.sentence.value;
	var anfrage = new XMLHttpRequest();
	var params = 'txtcmd='+encodeURIComponent(txtcmd)+'&layer='+encodeURIComponent(layer)+'&sentence='+encodeURIComponent(sentence);
	anfrage.open('POST', '/change_sentence');
	makeAnfrage(anfrage, params);
}
function newLayer(element) {
	var number = parseInt($(element).closest('tbody').prev().attr('no')) + 1;
	$.ajax({
		url: '/new_layer/' + (number)
	}).done(function(data) {
		$('#new-layer').closest('tbody').before(data);
		$('label[for^="combinations["][for$="[attr]]"]').closest('td').next().each(function(i){
			$(this).append("<input name='combinations["+i+"[attr["+number+"]]]' type='checkbox' value=''>\n<label for='combinations["+i+"[attr["+number+"]]]'></label>\n<br>");
		});
	});
}
function newCombination(element) {
	$.ajax({
		url: '/new_combination/' + (parseInt($(element).closest('tbody').prev().attr('no')) + 1)
	}).done(function(data) {
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
		$.ajax({
			url: '/'+type+'_form'
		})
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
	$.ajax({
		url: '/new_annotator/' + i
	}).done(function(data) {
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
	$.ajax({
		url: '/layer_options'
	})
	.done(function(data) {
		$('#layer').html(data);
		setSelectedIndex(document.getElementById('layer'), getCookie('traw_layer'));
	});
}
function build_sentence_list(list) {
	var sentence_select = $('#sentence');
	sentence_select.html('');
	$.each(list, function(sentence){
		if(this.found){
			sentence_select.append($('<option />').addClass('found_sentence').val(this.id).text(this.name));
		} else{
			sentence_select.append($('<option />').val(this.id).text(this.name));
		}
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
	$.ajax({
		url: '/import_form/' + type
	})
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
		if (data['sentence_list'] != undefined) {
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
	$.post('/go_to_step/' + i, {}, null, 'json')
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
