var Autocomplete = (function(){
	var $element = null;
	var $list = null;
	var splitInput = function() {
		var cursorPosition = $element[0].selectionDirection == 'backward' ? $element[0].selectionStart : $element[0].selectionEnd;
		var string = $element.val();
		var before = string.slice(0, cursorPosition).match(/(.*?)(\S*)$/);
		var after = string.slice(cursorPosition).match(/^\s*(.*)$/);
		var word = string.slice(cursorPosition).match(/^(\s|$)/) ? before[2] : '';
		return [before[1], word, after[1]];
	}
	var setProposals = function(input) {
		$list.text(input + 'blub');
	}
	var insert = function() {
		var word = $list.text();
		var segments = splitInput();
		upToCursor = segments[0] + word + ' ';
		$element.val(upToCursor + segments[2]);
		$element[0].setSelectionRange(upToCursor.length, upToCursor.length);
	}
	var disable = function() {
		$list.hide();
		$element.off('.autocomplete');
	}
	var keyBinding = function(e) {
		if (e.which == 9) {
			e.preventDefault();
			insert();
			disable();
		}
	}
	var inputHandler = function() {
		var word = splitInput()[1];
		if (word.length > 0) {
			setProposals(word);
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
