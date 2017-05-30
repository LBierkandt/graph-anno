var Log = (function () {
	var goToStep = function () {
		$.post('/go_to_step/' + $(this).attr('index'), {sentence: Sectioning.getCurrent()}, null, 'json')
		.done(function(data){
			Log.update();
			handleResponse(data);
		});
	}

	$(document).on('click', '#log tr[index]', goToStep);

	return {
		update: function () {
			$.getJSON('/get_log_update')
			.done(function(data){
				if (data['current_index'] == data['max_index']) {
					var currentStep = $('#log table tr[index="'+data['current_index']+'"]');
					if (currentStep.length == 0) {
						$('#log .content table').append(data['html']);
					} else {
						currentStep.replaceWith(data['html']);
					}
				}
				$('#log table tr[index]').each(function(){
					var index = $(this).attr('index');
					if (index > data['max_index']) $(this).remove();
					else if (index > data['current_index']) $(this).addClass('undone');
					else $(this).removeClass('undone') ;
				});
			});
		},
		load: function () {
			$('#log .content').load('/get_log_table');
		},
	}
})();
