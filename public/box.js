var Box = (function () {
	$(window).on('load', function(){
		// init boxes
		$('.box').each(function(){
			this.box = new Box($(this));
			$(this).draggable({handle: '.handle', stack: '.box', stop: Box.saveState});
		});
		// draggables on top when clicked
		$('.box').on('mouseup', function(){
			this.box.toFront(true);
		});
		// close button
		$('.handle').append('<div class="close"></div>')
		$(document).on('click', '.close', function(){
			$(this).closest('.box').hide();
			Box.saveState();
			$('#txtcmd').focus().select();
		});
		// button bar
		$(document).on('click', 'button[data-box]', function(){
			Box.instances[$(this).attr('data-box')].toggleAndSave();
		})
	});

	Box.instances = {};

	function Box($element) {
		this.$element = $element;
		this.id = $element.attr('id');
		this.restoreState();
		this.$element.resizable({
			handles: 'all',
			minHeight: $element.attr('min-height'),
			minWidth: $element.attr('min-width'),
			stop: Box.saveState}
		);
		Box.instances[this.id] = this;
	}

	Box.saveState = function() {
		var data = {};
		for (var id in Box.instances) {
			data[id] = {};
			for (var attr in {display: 0, left: 0, top: 0, width: 0, height: 0, 'z-index': 0}) {
				data[id][attr] = Box.instances[id].$element.css(attr);
			}
		}
		document.cookie = 'traw_windows=' + JSON.stringify(data) + '; expires=Fri, 31 Dec 9999 23:59:59 GMT';
		$.post('/save_window_positions', {data: data});
	}

	Box.prototype.restoreState = function(data) {
		if (data == undefined) {
			try {
				var attributes = JSON.parse(getCookie('traw_windows'))[this.id];
			} catch(e) {
				var attributes = {};
			}
		} else {
			var attributes = data[this.id];
		}
		for (var i in attributes) {
			this.$element.css(i, attributes[i]);
		}
		this.setButton();
	}

	Box.prototype.toggleAndSave = function(state) {
		this.$element.toggle(state);
		if (this.$element.css('display') == 'block') this.toFront(false);
		this.setButton();
		Box.saveState();
	}

	Box.prototype.setButton = function() {
		if (this.$element.css('display') == 'block') {
			$('#button-bar button[data-box=' + this.id + ']').addClass('active');
		} else {
			$('#button-bar button[data-box=' + this.id + ']').removeClass('active');
		}
	}

	Box.prototype.toFront = function(save) {
		if(!this.$element.hasClass('ui-draggable-dragging')){
			var zIndexList = $('.box').map(function(){return $(this).zIndex()}).get();
			var highestZIndex = Math.max.apply(null, zIndexList);
			if(this.$element.zIndex() < highestZIndex){
				this.$element.zIndex(highestZIndex + 1);
				if (save) Box.saveState();
			}
		}
	}

	return Box;
})();
