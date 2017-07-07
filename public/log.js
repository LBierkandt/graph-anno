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
