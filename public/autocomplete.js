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

var Autocomplete = (function(){
	var $element = null;
	var $list = null;
	var value = '';
	var noInput = false;

	var parseInput = function() {
		var cursorPosition = $element[0].selectionDirection == 'backward' ? $element[0].selectionStart : $element[0].selectionEnd;
		var string = $element.val();
		var command = string.match(/^\s*\S+\s/) ? string.match(/^\s*(\S+)/)[1] : '';
		var suggestionSet = window.autocompleteCommands[command];
		var before = string.slice(0, cursorPosition).match(suggestionSet == 'file' ? /^(.*(\s|^))(\S*)$/ : /^(.*(\.\.|\s|^))(\S*)$/);
		var after = string.slice(cursorPosition).match(/^\s*(.*)$/);
		var word = string.slice(cursorPosition).match(/^(\s|$)/) ? before[3] : '';
		var sep = suggestionSet == 'file' ? '/' : null;
		var wordParts = word.match(sep) ? word.match('^(.*' + sep + ')([^'+ sep + ']*)$') : [null, '', word];
		return {
			before: before[1],
			command: command,
			word: word,
			retain: wordParts[1],
			replace: wordParts[2],
			after: after[1],
			suggestionSet: suggestionSet,
			layer: document.cmd.layer.value,
		};
	}
	var setList = function(words) {
		$list.html('').scrollTop(0);
		words.forEach(function(word){
			$list.append('<div>' + word + '</div>');
		});
		$list.children(':first-child').addClass('active');
	}
	var insert = function() {
		var word = $list.find('.active').text();
		var input = parseInput();
		if (input.suggestionSet == 'file' && word.match(/\/$/)) var upToCursor = input.before + input.retain + word;
		else var upToCursor = input.before + input.retain + word + ' ';
		$element.val(upToCursor + input.after);
		$element[0].setSelectionRange(upToCursor.length, upToCursor.length);
		if (input.suggestionSet == 'command') handleInput();
		if (input.suggestionSet == 'file' && word.match(/\/$/)) handleInput();
	}
	var disable = function() {
		$list.hide();
		$element.off('.autocomplete');
	}
	var changeActive = function(keycode) {
		var active = $list.find('.active');
		if (keycode == 38) {
			var newActive = active.prev();
			if (newActive.length == 0) newActive = $list.children(':last-child');
		} else if (keycode == 40) {
			var newActive = active.next();
			if (newActive.length == 0) newActive = $list.children(':first-child');
		}
		$list.children().removeClass('active');
		newActive.addClass('active');
		scrollIntoView('.active');
	}
	var scrollIntoView = function () {
		var $element = $('#autocomplete .active');
		if ($element.length == 0) return;
		var $container = $('#autocomplete');
		var containerViewTop = $container.scrollTop();
		var containerViewHeight = $container[0].clientHeight;
		var containerViewBottom = containerViewTop + containerViewHeight;
		var elementTop = Math.ceil($element.position().top + containerViewTop);
		var elementBottom = Math.ceil(elementTop + $element.height());
		if (elementTop < containerViewTop)
			$container.scrollTop($element.position().top);
		else if (elementBottom > containerViewBottom) {
			$container.scrollTop(elementTop + $element.height() - containerViewHeight);
		}
	}
	var keyBinding = function(e) {
		var actions = {
			9: function() {insert(); disable();},
			27: disable,
			38: changeActive,
			40: changeActive,
		};
		if (e.which in actions) {
			e.preventDefault();
			noInput = true;
			actions[e.which](e.which);
		}
	}
	var saveValue = function() {
		value = $element.val();
	}
	var valueUnchanged = function() {
		return $element.val() == value;
	}
	var handleInput = function(e) {
		if (!window.preferences.autocompletion) return;
		if (valueUnchanged()) return;
		if (noInput) {noInput = false; return;}
		var input = parseInput();
		if (input.word.length > 0 || input.suggestionSet == 'file') {
			if (!input.suggestionSet) return;
			$.getJSON('/get_autocomplete_suggestions/', input).done(function(suggestions){
				showSuggestions(input, suggestions);
			});
		} else {
			disable();
		}
	}
	var showSuggestions = function(input, suggestions) {
		if (suggestions.length > 0) {
			setList(suggestions.sort());
			if ($list.css('display') == 'none') {
				var coordinates = getCaretCoordinates($element[0], $element[0].selectionEnd);
				$list.css({left: coordinates.left}).show();
				$element.on('keydown.autocomplete', keyBinding);
			}
		} else {
			disable();
		}
	}

	return {
		init: function(selector) {
			$element = $(selector);
			$list = $('<div id="autocomplete"></div>').appendTo($element.parent());
			$element.on('keydown', saveValue);
			$element.on('keyup', handleInput);
		},
		disable: disable,
	}
})();
