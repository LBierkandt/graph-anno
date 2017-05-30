var GraphDisplay = (function () {
	var $graphdiv = null;
	var $svg = null;
	var originalSvgSize = null;
	var foundFragments = [];
	var currentFragmentIndex = -1;

	var setGraphdiv = function() {
		$graphdiv = $('#graph');
	}
	var setFoundFragments = function(fragments) {
		foundFragments = fragments;
		currentFragmentIndex = -1;
	}
	var fitGraphdiv = function() {
		$graphdiv.height(window.innerHeight - $('#bottom').height());
	}
	var fitGraph = function() {
		var $svg = $graphdiv.find('svg');
		var outerHeight = $graphdiv.height() - 20;
		var newHeight = Math.min(outerHeight, $svg.height());
		$svg.width($svg.width() / $svg.height() * newHeight);
		$svg.height(newHeight);
		$svg.css('top', outerHeight - $svg.height());
	}
	var tieToBottom = function() {
		$svg.css('top', Math.max(($graphdiv.height()-20) - $svg.height(), 0));
	}
	var scaleGraph = function(richtung) {
		var xmitte = $graphdiv.scrollLeft() + $graphdiv.width() / 2;
		var ymitte = $graphdiv.scrollTop() + $graphdiv.height() / 2;
		var faktor = 1;
		if (richtung == '+') {faktor = 1.25}
		else if (richtung == '-') {faktor = 0.8}
		$svg.width($svg.width() * faktor);
		$svg.height($svg.height() * faktor);
		$graphdiv.scrollLeft(xmitte * faktor - $graphdiv.width() / 2);
		$graphdiv.scrollTop(ymitte * faktor - $graphdiv.height() / 2);
		tieToBottom();
	}
	var moveGraph = function(direction) {
		switch (direction) {
			case 'oo': $graphdiv[0].scrollTop = 0; break;
			case 'uu': $graphdiv[0].scrollTop = 999999; break;
			case 'a': $graphdiv[0].scrollLeft = 0; break;
			case 'e': $graphdiv[0].scrollLeft = 999999; break;
			case 'l': $graphdiv[0].scrollLeft -= 50; break;
			case 'o': $graphdiv[0].scrollTop -= 50; break;
			case 'r': $graphdiv[0].scrollLeft += 50; break;
			case 'u': $graphdiv[0].scrollTop += 50; break;
		}
	}
	var jumpToFragment = function(direction) {
		if (!foundFragments || foundFragments.length < 1) return;
		foundFragments.sort(function(a, b){
			return getPosition(a).centerX - getPosition(b).centerX;
		});
		// find previous/next graph fragment
		if (direction == 'prev') {
			if (currentFragmentIndex == -1)
				currentFragmentIndex = foundFragments.length - 1;
			else
				currentFragmentIndex = Math.max(currentFragmentIndex - 1, 0);
		} else {
			currentFragmentIndex = Math.min(currentFragmentIndex + 1, foundFragments.length - 1);
		}
		// center graph fragment
		var position = getPosition(foundFragments[currentFragmentIndex])
		$graphdiv.scrollLeft(position.centerX + $graphdiv.scrollLeft() - $graphdiv.width() / 2);
		$graphdiv.scrollTop(position.centerY + $graphdiv.scrollTop() - $graphdiv.height() / 2);
	}
	var getPosition = function(fragment) {
		var position = {};
		var fragmentElements = fragment.map(function(id){
			return $svg.find('g#' + id);
		});
		position.left = Math.min.apply(null, fragmentElements.map(function($element){
			return $element[0].getBoundingClientRect().left;
		}));
		position.top = Math.min.apply(null, fragmentElements.map(function($element){
			return $element[0].getBoundingClientRect().top;
		}));
		position.right = Math.max.apply(null, fragmentElements.map(function($element){
			return $element[0].getBoundingClientRect().right;
		}));
		position.bottom = Math.max.apply(null, fragmentElements.map(function($element){
			return $element[0].getBoundingClientRect().bottom;
		}));
		position.centerX = (position.right + position.left) / 2;
		position.centerY = (position.bottom + position.top) / 2;
		return position;
	}
	var updateView = function(data) {
		data = data || {};
		fitGraphdiv();
		if (!data.dot) return;
		// get old dimensions
		$svg = $graphdiv.find('svg');
		var oldImageSize = {
			width: $svg.width() || 1,
			height: $svg.height() || 1,
		};
		if (!originalSvgSize) originalSvgSize = oldImageSize;
		// create svg
		try {
			var svgElement = new DOMParser().parseFromString(Viz(data.dot, 'svg'), 'image/svg+xml');
		} catch(e) {
			alert('An error occurred while generating the graph. Try reloading your browser window or restarting your browser; if that doesn’t help, try the edge label compatibility mode (see config window)');
			return;
		}
		// get new dimensions
		var newSvgSize = {
			width: parseInt(svgElement.documentElement.getAttribute('width')),
			height: parseInt(svgElement.documentElement.getAttribute('height')),
		};
		// insert svg
		$graphdiv.empty().append(svgElement.documentElement);
		$svg = $graphdiv.find('svg');
		// scale svg
		if (data.sections_changed) {
			$svg.width(newSvgSize.width);
			$svg.height(newSvgSize.height);
			fitGraph();
		} else {
			$svg.width(newSvgSize.width * oldImageSize.width / originalSvgSize.width);
			$svg.height(newSvgSize.height * oldImageSize.height / originalSvgSize.height);
			if ($graphdiv.scrollTop() == 0) tieToBottom($svg, $graphdiv);
		}
		originalSvgSize = newSvgSize;
	}
	var saveImage = function(format) {
		var width = parseInt($svg.attr('width'));
		var height = parseInt($svg.attr('height'));
		var url = 'data:image/svg+xml;base64,' +
			window.btoa(unescape(encodeURIComponent(
				[
					'<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
					'<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">',
					$graphdiv.html(),
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
	var downloadFile = function(url, format) {
		var link = $('<a></a>').appendTo($('body'));
		link.attr('href', url).attr('download', 'image.' + format)
			.css('display', 'none')
			.get(0).click();
		link.remove();
	}

	$(document).ready(setGraphdiv);
	$(window).on('resize', fitGraphdiv);

	return {
		fitGraph: fitGraph,
		fitGraphdiv: fitGraphdiv,
		jumpToFragment: jumpToFragment,
		moveGraph: moveGraph,
		saveImage: saveImage,
		scaleGraph: scaleGraph,
		setFoundFragments: setFoundFragments,
		updateView: updateView,
	}
})();
