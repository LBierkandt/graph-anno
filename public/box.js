var Box = (function () {
	$(window).on('load', function(){
		// init boxes
		$('.box').each(function(){
			new Box($(this));
			$(this).draggable({handle: '.handle', stack: '.box', stop: Box.saveState});
		});
		// draggables on top when clicked
		$('.box').on('mouseup', function(){
			var $box = $(this);
			if(!$box.hasClass('ui-draggable-dragging')){
				var zIndexList = $('.box').map(function(){return $(this).zIndex()}).get();
				var highestZIndex = Math.max.apply(null, zIndexList);
				if($box.zIndex() < highestZIndex){
					$box.zIndex(highestZIndex + 1);
					Box.saveState();
				}
			}
		});
		// close button
		$('.handle').html('<div class="close"></div>')
		$(document).on('click', '.close', function(){
			$(this).closest('.box').hide();
			Box.saveState();
			$('#txtcmd').focus().select();
		});
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
	}

	Box.prototype.toggleAndSave = function(state) {
		this.$element.toggle(state);
		Box.saveState();
	}

	return Box;
})();
