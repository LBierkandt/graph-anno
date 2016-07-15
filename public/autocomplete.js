var Autocomplete = (function(){
	var $element = null;
	var $list = null;
	var noInput = false;
	var data = {
		anno: ['cat:S', 'cat:R', 'cat:Z', 'tns:prs', 'tns:prt', 'tns:fut', 'mod:ind', 'mod:subj'],
	};

	var parseInput = function() {
		var cursorPosition = $element[0].selectionDirection == 'backward' ? $element[0].selectionStart : $element[0].selectionEnd;
		var string = $element.val();
		var before = string.slice(0, cursorPosition).match(/(.*?)(\S*)$/);
		var after = string.slice(cursorPosition).match(/^\s*(.*)$/);
		var word = string.slice(cursorPosition).match(/^(\s|$)/) ? before[2] : '';
		var context = before[1][before[1].length - 1];
		return {
			before: before[1],
			word: word,
			after: after[1],
			context: context
		};
	}
	var setSuggestions = function(input, context) {
		var suggestionSet = 'anno';
		var words = [];
		var suggestionData = data[suggestionSet];
		for (var i in suggestionData) {
			if (suggestionData[i].slice(0, input.length) == input) words.push(suggestionData[i]);
		}
		setList(words);
	}
	var setList = function(words) {
		$list.html('');
		for (var i in words) {
			$list.append('<div>' + words[i] + '</div>');
		}
		$list.children(':first-child').addClass('active');
	}
	var insert = function() {
		var word = $list.find('.active').text();
		var segments = parseInput();
		upToCursor = segments.before + word + ' ';
		$element.val(upToCursor + segments.after);
		$element[0].setSelectionRange(upToCursor.length, upToCursor.length);
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
	var inputHandler = function(e) {
		if (noInput) {noInput = false; return;}
		var segments = parseInput();
		if (segments.word.length > 0 && segments.context) {
			setSuggestions(segments.word, segments.context);
			if ($list.css('display') == 'none') {
				var coordinates = getCaretCoordinates(this, this.selectionEnd);
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
			$element.on('keyup', inputHandler);
		}
	}
})();
