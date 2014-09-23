window.onload = function() {
	loadGraph();
	
	window.onkeydown = taste;
	document.getElementById('sentence').onchange = changeSentence;
	
	document.forms['cmd'].elements['txtcmd'].focus();
	document.forms['cmd'].elements['txtcmd'].select();
}
window.onresize = graphdivEinpassen;

function loadGraph() {
	var anfrage = new XMLHttpRequest();
	anfrage.open('GET', '/graph', false);
	anfrage.onreadystatechange = function () {
		if (anfrage.readyState == 4 && anfrage.status == 200) {
			var antworthash = JSON.parse(anfrage.responseText);
			updateView(antworthash);
		}
	}
	anfrage.send(null);
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
		var help = document.getElementById('help');
		help.style.display = (help.style.display != 'block') ? 'block' : 'none';
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
		var anfrage = new XMLHttpRequest();
		anfrage.open('GET', '/toggle_refs');
		anfrage.onreadystatechange = function () {
			if (anfrage.readyState == 4 && anfrage.status == 200) {
				var antworthash = JSON.parse(anfrage.responseText);
				updateView(antworthash);
			}
		}
		anfrage.send(null);
	}
	else if (tast.which == 117) {
		tast.preventDefault();
		var filter = document.getElementById('filter');
		if (filter.style.display != 'block') {
			filter.style.display = 'block';
			document.getElementById('filterfield').focus();
		}
		else {
			filter.style.display = 'none';
			document.forms['cmd'].elements['txtcmd'].focus();
			document.forms['cmd'].elements['txtcmd'].select();
		}
	}
	else if (tast.which == 118) {
		tast.preventDefault();
		var search = document.getElementById('search');
		if (search.style.display != 'block') {
			search.style.display = 'block';
			document.getElementById('query').focus();
		}
		else {
			search.style.display = 'none';
			document.forms['cmd'].elements['txtcmd'].focus();
			document.forms['cmd'].elements['txtcmd'].select();
		}
	}
	else if (tast.which == 119) {
		tast.preventDefault();
		openConfig();
	}
	else if (tast.altKey && tast.which == 37) {
		tast.preventDefault();
		var sentenceField = document.getElementById('sentence');
		sentenceField.selectedIndex = Math.max(sentenceField.selectedIndex - 1, 0);
		changeSentence();
	}
	else if (tast.altKey && tast.which == 39) {
		tast.preventDefault();
		var sentenceField = document.getElementById('sentence');
		sentenceField.selectedIndex = Math.min(sentenceField.selectedIndex + 1, sentenceField.options.length - 1);
		changeSentence();
	}
	else if (tast.altKey && tast.which == 36) {
		tast.preventDefault();
		var sentenceField = document.getElementById('sentence');
		sentenceField.selectedIndex = 0;
		changeSentence();
	}
	else if (tast.altKey && tast.which == 35) {
		tast.preventDefault();
		var sentenceField = document.getElementById('sentence');
		sentenceField.selectedIndex = sentenceField.options.length - 1;
		changeSentence();
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
function updateView(antworthash) {
	document.getElementById('textline').innerHTML = antworthash['textline'];
	document.getElementById('meta').innerHTML = antworthash['meta'];
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
	var sentence = document.cmd.sentence.value;
	var anfrage = new XMLHttpRequest();
	var params = 'txtcmd='+encodeURIComponent(txtcmd)+'&layer='+encodeURIComponent(layer)+'&sentence='+encodeURIComponent(sentence);
	anfrage.open('POST', '/commandline');
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
	//document.forms['cmd'].elements['txtcmd'].focus();
	//document.forms['cmd'].elements['txtcmd'].select();

}
function sendSearch() {
	var query = document.search.query.value;
	var anfrage = new XMLHttpRequest();
	var params = 'query=' + encodeURIComponent(query);
	anfrage.open('POST', '/search');
	makeAnfrage(anfrage, params);
}
function sendDataExport() {
	var query = document.search.query.value;
	var anfrage = new XMLHttpRequest();
	var params = '?query=' + encodeURIComponent(query);
	anfrage.open('GET', '/export_data' + params);
	anfrage.onreadystatechange = function () {
		if (anfrage.readyState == 4 && anfrage.status == 200) {
			if (anfrage.responseText == '') {
				location = "/export/data_table.csv";
			} else {
				alert(anfrage.responseText);
			}
		}
	}
	anfrage.send(params);
}
function setSelectedIndex(s, v) {
	for ( var i = 0; i < s.options.length; i++ ) {
		if ( s.options[i].text == v ) {
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
		anfrage.setRequestHeader("Content-length", params.length);
		anfrage.setRequestHeader("Connection", "close");
		anfrage.onreadystatechange = function() {
			if (this.readyState == 4 && this.status == 200) {
				var antworthash = JSON.parse(this.responseText);
				if (antworthash['modal'] == 'import') {
					openImport();
					return;
				}
				var txtcmd = document.getElementById('txtcmd');
				txtcmd.value = getCookie('traw_cmd');
				if (antworthash['sentences_html'] != undefined) document.cmd.sentence.innerHTML = antworthash['sentences_html'];
				updateLayerOptions();
				setSelectedIndex(document.getElementById('sentence'), getCookie('traw_sentence'));
				if (antworthash['graph_file'] != undefined) document.getElementById('active_file').innerHTML = 'file: '+antworthash['graph_file'];
				if (antworthash['search_result'] != undefined) {
					document.getElementById('searchresult').innerHTML = antworthash['search_result'];
					query.focus();
				} else if (antworthash['filter_applied'] != undefined) {
					filterfield.focus();
				} else {
					txtcmd.focus();
					txtcmd.select();
				}
				updateView(antworthash);
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
	anfrage.open('POST', '/sentence');
	makeAnfrage(anfrage, params);
}
function openConfig() {
	if ($('#modal-background').css('display') != 'block') {
		$.ajax({
			type: 'GET',
			url: '/config'
		})
		.done(function(data) {
			$('#modal-content').html(data);
			$('.remove-layer').click(function() {
				$(this).closest('tbody').remove();
				removeLayerAttributes();
			});
			$('.remove-combination').click(function() {
				$(this).closest('tbody').remove();
			});
			$('#new-layer').click(function() {
				var number = parseInt($(this).closest('tbody').prev().attr('no')) + 1;
				$.ajax({
					url: '/new_layer/' + (number)
				}).done(function(data) {
					$('#new-layer').closest('tbody').before(data);
					$('label[for^="combinations["][for$="[attr]]"]').closest('td').next().each(function(i){
						$(this).append("<input name='combinations["+i+"[attr["+number+"]]]' type='checkbox' value=''>\n<label for='combinations["+i+"[attr["+number+"]]]'></label>\n<br>");
					});
				});
				return false;
			});
			$('#new-combination').click(function() {
				$.ajax({
					url: '/new_combination/' + (parseInt($(this).closest('tbody').prev().attr('no')) + 1)
				}).done(function(data) {
					$('#new-combination').closest('tbody').before(data);
					removeLayerAttributes();
					$('input[name^="layers["][name$="[attr]]"]').each(function(i){
					  setLayerAttributes(this);
					});
				});
				return false;
			});
			$('#modal-background').show();
			window.onkeydown = configKeys;
		});
	}
}
function sendConfig() {
	$.ajax({
		type: 'POST',
		url: '/config',
		async: true,
		dataType: 'json',
		data: $('#modal-form').serialize()
	})
	.done(function(data) {
		if (data == true) {
			closeModal();
			updateLayerOptions();
			loadGraph();
		} else {
			$('#modal-warning').html('Invalid values – check your input!');
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
function closeModal() {
	$('#modal-background').hide();
	$('#txtcmd').focus();
	window.onkeydown = taste;
}
function updateLayerOptions() {
	$.ajax({
		type: 'GET',
		url: '/layer_options'
	})
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
function openImport() {
	$.ajax({
		type: 'GET',
		url: '/import'
	})
	.done(function(data) {
		$('#modal-content').html(data);
		disable_import_form_fields();
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
function sendImport() {
	var formData = new FormData($('#modal-form')[0]);
	$.ajax({
			url: '/import',
			type: 'POST',
			data: formData,
			dataType: 'json',
			//Options to tell jQuery not to process data or worry about content-type.
			cache: false,
			contentType: false,
			processData: false
	})
	.done(function(data) {
		if (data == true) {
			closeModal();
			updateLayerOptions();
			sendCmd('');
		} else {
			$('#modal-warning').html('Invalid values – check your input!');
			$('#modal-form label').removeClass('error_message');
			for (var i in data) {
				$('label[for="' + i + '"]').addClass('error_message');
			}
		}
	})
	.error(function(data) {
		alert('An error occurred while importing.');
	});
}
function disable_import_form_fields() {
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