var Autocomplete = (function(){
	var $element = null;
	var $list = null;
	var value = '';
	var noInput = false;
	var data = {};

	var parseInput = function() {
		var cursorPosition = $element[0].selectionDirection == 'backward' ? $element[0].selectionStart : $element[0].selectionEnd;
		var string = $element.val();
		var before = string.slice(0, cursorPosition).match(/^(.*?)(\S*)$/);
		var after = string.slice(cursorPosition).match(/^\s*(.*)$/);
		var word = string.slice(cursorPosition).match(/^(\s|$)/) ? before[2] : '';
		var context = before[1].replace(/^\s+/, '')[before[1].length - 1];
		var command = context ? string.match(/^\s*(\S+)/)[1] : null;
		return {
			before: before[1],
			word: word,
			after: after[1],
			suggestionSet: data.commands[command],
		};
	}
	var setList = function(words) {
		$list.html('');
		words.forEach(function(word){
			$list.append('<div>' + word + '</div>');
		});
		$list.children(':first-child').addClass('active');
	}
	var insert = function() {
		var word = $list.find('.active').text();
		var input = parseInput();
		var upToCursor = input.before + word + (input.suggestionSet == 'file' ? '' : ' ');
		$element.val(upToCursor + input.after);
		$element[0].setSelectionRange(upToCursor.length, upToCursor.length);
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
		if (valueUnchanged()) return;
		if (noInput) {noInput = false; return;}
		var input = parseInput();
		if (input.word.length > 0) {
			if (input.suggestionSet == 'file') {
				$.getJSON('/get_file_list/', {input: input.word}).done(function(suggestions){
					showSuggestions(input, suggestions);
				});
			} else {
				var suggestionData = input.suggestionSet ? data[input.suggestionSet] : Object.keys(data.commands);
				var suggestions = suggestionData.filter(function(suggestion){
					return (suggestion.slice(0, input.word.length) == input.word);
				});
				showSuggestions(input, suggestions);
			}
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
		setData: function(newData) {
			if (newData) data = newData;
		},
	}
})();
