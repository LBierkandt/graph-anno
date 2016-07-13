var Autocomplete = (function(){
	var $element = null;
	var $list = null;
	var insertProposals = function(input) {
		$list.text(input + 'blub');
	}
	var disable = function() {
		$list.hide();
		$element.off('.autocomplete');
	}
	var keyBinding = function(e) {
		if (e.which == 9) {
			e.preventDefault();
			var words = $element.val().split(' ');
			var word = $list.text();
			$element.val(words.slice(0, words.length - 1).join(' ') + ' ' + word + ' ');
			disable();
		}
	}
	var inputHandler = function() {
		var words = $element.val().split(' ');
		var word = words[words.length - 1];
		if (word.length > 0) {
			insertProposals(word);
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
			$element.on('input', inputHandler);
		}
	}
})();
