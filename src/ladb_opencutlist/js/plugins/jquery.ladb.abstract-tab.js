'use strict';

function LadbAbstractTab(element, options, opencutlist) {
    this.options = options;
    this.$element = $(element);
    this.opencutlist = opencutlist;

    this._commands = {};

    this._$modal = null;
}

// Modal /////

LadbAbstractTab.prototype.appendModalInside = function(id, twigFile, renderParams) {
    var that = this;

    // Hide previously opened modal
    if (this._$modal) {
        this._$modal.modal('hide');
    }

    // Render modal
    this.$element.append(Twig.twig({ref: twigFile}).render(renderParams));

    // Fetch UI elements
    this._$modal = $('#' + id, this.$element);

    // Add modal extra classes
    this._$modal.addClass('modal-inside');

    // Bind modal
    this._$modal.on('shown.bs.modal', function () {
        $('body > .modal-backdrop').first().appendTo(that.$element);
        $('body')
            .removeClass('modal-open')
            .css('padding-right', 0);
    });
    this._$modal.on('hidden.bs.modal', function () {
        $(this)
            .data('bs.modal', null)
            .remove();
    });

    return this._$modal;
};

// Action /////

LadbAbstractTab.prototype.registerCommand = function(command, block) {
    if (typeof(block) == 'function') {
        this._commands[command] = block;
    } else {
        alert('Action\'s block must be a function');
    }
};

LadbAbstractTab.prototype.executeCommand = function(command, parameters, callback) {
    if (this._commands.hasOwnProperty(command)) {

        // Retrieve action block
        var block = this._commands[command];

        // Execute action block with parameters
        block(parameters);

        // Invoke the callback
        if (typeof(callback) == 'function') {
            callback();
        }

    } else {
        alert('Command ' + command + ' not found');
    }
};