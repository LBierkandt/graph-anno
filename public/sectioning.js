var Sectioning = (function () {
	var list = [];
	var index = {};
	var current = [];
	var currentIndizes = [];
	var currentLevel = 0
	var clickedLevel = 0
	var clickedElement = null;
	var keyBinding = function (e) {
		switch (e.which) {
			case 13:
				Sectioning.setCurrent($.map($('.section.chosen'), function(el){return $(el).attr('section-id');}));
				unchoose(e);
				Sectioning.changeSentence();
				break;
			case 27:
				unchoose(e);
				break;
			case 38:
			case 40:
				chooseByKey(e);
				break;
		}
	}
	var chooseByKey = function (e) {
		e.preventDefault();
		var $sections = $('ul[level="'+clickedLevel+'"] .section');
		var index = $sections.index(clickedElement);
		if (e.which == 38 && index > 0) {
			var direction = -1;
		} else if (e.which == 40 && index < $sections.length - 1) {
			var direction = 1;
		}
		if (direction == undefined) return;
		if (e.shiftKey) {
			if ($sections.slice(index + direction, index + direction + 1).hasClass('chosen')) clickedElement.removeClass('chosen');
		} else {
			$sections.removeClass('chosen');
		}
		clickedElement = $sections.slice(index + direction, index + direction + 1).addClass('chosen');
		scroll('.chosen');
	}
	var scroll = function (klass) {
		var margin = 2;
		var $elements = $('.section' + klass);
		if ($elements.length == 0) return;
		var $firstElement = $elements.first();
		var $lastElement = $elements.last();
		var $container = $('#sectioning .content');
		var containerViewTop = $container.scrollTop();
		var containerViewHeight = $container[0].clientHeight;
		var containerViewBottom = containerViewTop + containerViewHeight;
		var firstElementTop = Math.ceil($firstElement.position().top + margin);
		var lastElementTop = Math.ceil($lastElement.position().top + margin);
		var lastElementBottom = Math.ceil(lastElementTop + $lastElement.height() + 2*margin);
		var elementHeight = Math.ceil(lastElementTop - firstElementTop + $lastElement.height() + margin);
		if (firstElementTop < containerViewTop || elementHeight > containerViewHeight)
			$container.scrollTop($firstElement.position().top);
		else if (lastElementBottom > containerViewBottom)
			$container.scrollTop(firstElementTop + elementHeight - containerViewHeight + margin);
	}
	var click = function (e) {
		clickedElement = e.target.closest('.section');
		var newclickedLevel = $(e.target).closest('ul').attr('level');
		if (newclickedLevel != clickedLevel) {
			$('.section').removeClass('chosen');
		}
		clickedLevel = newclickedLevel;
		$(window).off('keydown', keyBinding).on('keydown', keyBinding);
		if (e.ctrlKey) {
			$(clickedElement).toggleClass('chosen');
		} else if (e.shiftKey) {
			var $sections = $('ul[level="'+clickedLevel+'"] .section');
			var firstIndex = $sections.index($('.section.chosen').first());
			var lastIndex = $sections.index($('.section.chosen').last());
			var clickedIndex = $sections.index(clickedElement);
			if (firstIndex == -1) {
				$(clickedElement).addClass('chosen');
			} else if (clickedIndex < firstIndex) {
				$sections.slice(clickedIndex, firstIndex).addClass('chosen');
			} else if (clickedIndex > lastIndex) {
				$sections.slice(lastIndex, clickedIndex + 1).addClass('chosen');
			} else if (clickedIndex > firstIndex && clickedIndex < lastIndex) {
				if ($(clickedElement).hasClass('chosen'))
					$sections.slice(clickedIndex, lastIndex + 1).removeClass('chosen');
				else
					$sections.slice(firstIndex, clickedIndex + 1).addClass('chosen');
			} else {
				$(clickedElement).toggleClass('chosen');
			}
		} else {
			$('.section').removeClass('chosen');
			$(clickedElement).addClass('chosen');
		}
	}
	var dblclick = function (e) {
		unchoose(e);
		Sectioning.setCurrent([$(this).attr('section-id')]);
		Sectioning.changeSentence();
	}
	var unchoose = function (e) {
		e.preventDefault();
		$(window).off('keydown', keyBinding);
		$('.section').removeClass('chosen');
	}
	var setContent = function ($el, section, level) {
		$el.html('<span class="sentence-name">' + (section.name || '') + '</span>');
		if (level == 0) $el.append(': <span class="sentence-start">' + section.text + '</span>')
	}
	var sentenceWithMatch = function (dir) {
		newIndex = list[currentLevel][currentIndizes[0]][dir == 1 ? 'last' : 'first'];
		negIndex = newIndex - list[0].length;
		for (var i = (dir == 1 ? negIndex : newIndex) + dir; i != (dir == 1 ? newIndex : negIndex); i += dir) {
			if (list[0].slice(i)[0].found) return list[0].slice(i)[0].first;
		}
		return newIndex;
	}
	var sectionWithMatch = function (originalLevel, sentenceIndex) {
		for (var level = originalLevel; level > 0; level--) {
			for (var i in list[level]) {
				if (list[level][i].first <= sentenceIndex && list[level][i].last >= sentenceIndex) {
					currentLevel = level;
					return i;
				}
			}
		}
		currentLevel = 0;
		return sentenceIndex;
	}

	$(document).on('dblclick', '#sectioning .section', dblclick);
	$(document).on('click', '#sectioning .section', click);

	return {
		setList: function (data) {
			list = data;
			$('#sectioning .content').html('');
			for (var level = list.length - 1; level >= 0; level--) {
				var ul = $(document.createElement('ul')).appendTo('#sectioning .content')
				.attr('level', level)
				.css('left', (list.length - level - 1) * 86 + 2);
				for (var i in list[level]) {
					var section = list[level][i];
					index[section.id] = section;
					var li = $(document.createElement('li')).appendTo(ul)
					.addClass('section')
					.css('top', section.first * 18)
					.css('height', (section.last - section.first) * 18 + 16)
					.attr('section-id', section.id)
					if (section.found) li.addClass('found_sentence')
					setContent(li, section, level);
				}
			}
		},
		updateList: function (data) {
			for (var i in data) {
				var section = data[i];
				for (var prop in section) index[section.id][prop] = section[prop];
				var li = $('[section-id=' + section.id + ']');
				var level = parseInt(li.closest('ul').attr('level'));
				setContent(li, section, level);
			}
		},
		setCurrent: function (sections) {
			current = sections;
			currentLevel = parseInt($('.section[section-id="'+current[0]+'"]').closest('ul').attr('level'))
			currentIndizes = [];
			$('.section').removeClass('active');
			for (var i in current) {
				$('.section[section-id="'+current[i]+'"]').addClass('active');
				var index = $.map(list[currentLevel], function(e){return e.id.toString();}).indexOf(current[i]);
				currentIndizes.push(index);
			}
			scroll('.active');
		},
		selection: function (direction, shiftPressed) {
			$(window).off('keydown', keyBinding).on('keydown', keyBinding);
			var sections = $('ul[level="'+currentLevel+'"] .section');
			clickedLevel = currentLevel;
			if (direction == 'up') {
				clickedElement = $(sections[currentIndizes[0]]);
			} else if (direction == 'down') {
				clickedElement = $(sections[currentIndizes[currentIndizes.length - 1]]);
			}
			$('.section').removeClass('chosen');
			for (var i in currentIndizes) {
				var chosen = $(sections[currentIndizes[i]]).addClass('chosen');
			}
			scroll('.chosen');
		},
		setCurrentIndizes: function (level, indizes) {
			currentLevel = level;
			currentIndizes = indizes;
			current = [];
			$('.section').removeClass('active');
			var sections = $('ul[level="'+currentLevel+'"] .section');
			for (var i in currentIndizes) {
				var active = $(sections[currentIndizes[i]]).addClass('active');
				current.push(active.attr('section-id'));
			}
			scroll('.active');
		},
		getCurrent: function () {
			return current;
		},
		changeSentence: function () {
			postRequest('/change_sentence', {sentence: current});
		},
		navigateSentences: function (target) {
			var newIndizes = currentIndizes;
			switch(target) {
				case 'first':
					var offset = currentIndizes[0];
					if (offset > 0)
						newIndizes = $.map(currentIndizes, function(i){return i - offset;});
					break;
				case 'prev':
					if (currentIndizes[0] > 0)
						newIndizes = $.map(currentIndizes, function(i){return i - 1;});
					break;
				case 'next':
					if (currentIndizes[currentIndizes.length - 1] < list[currentLevel].length - 1)
						newIndizes = $.map(currentIndizes, function(i){return i + 1;});
					break;
				case 'last':
					var offset = list[currentLevel].length - 1 - currentIndizes[currentIndizes.length - 1];
					if (offset > 0)
						newIndizes = $.map(currentIndizes, function(i){return i + offset;});
					break;
				case 'prevMatch':
					newIndizes = [sectionWithMatch(currentLevel, sentenceWithMatch(-1))];
					break;
				case 'nextMatch':
					newIndizes = [sectionWithMatch(currentLevel, sentenceWithMatch(+1))];
					break;
			}
			if (JSON.stringify(newIndizes) != JSON.stringify(currentIndizes)) {
				Sectioning.setCurrentIndizes(currentLevel, newIndizes);
				Sectioning.changeSentence()
			}
		},
	}
})();
