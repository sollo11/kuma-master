(function ($) {
    'use strict';

    var $revisionReplaceBlock = $('#revision-replace-block');
    var $localeInput = $('#id_locale');
    var $filterForm = $('#revision-filter');
    var $pageInput = $('#revision-page');
    var currentLocale = $('html').attr('lang');
    var controlsTemplate = '' +
    '<div class="action-bar">' +
        '<ul id="page-buttons">' +
            '<li><a id="revert" href="$reverturl" class="button">' + gettext('Revert') + '<i aria-hidden="true" class="icon-undo"></i></a></li>' +
            '<li><a id="view" href="$viewurl" class="button">' + gettext('View Page') + '<i aria-hidden="true" class="icon-circle-arrow-right"></i></a></li>' +
            '<li class="page-edit"><a id="edit" href="$editurl" class="button">' + gettext('Edit Page') + '<i aria-hidden="true" class="icon-pencil"></i></a></li>' +
            '<li class="page-history"><a id="history" href="$historyurl" class="button">' + gettext('History') + '<i aria-hidden="true" class="icon-book"></i></a></li>' +
        '</ul>' +
    '</div>';

    // Create the autocomplete for user
    $('#id_user').mozillaAutocomplete({
        minLength: 3,
        labelField: 'label',
        autocompleteUrl: '/' + currentLocale + '/dashboards/user_lookup',
        buildRequestData: function (req) {
            // Should add locale value here
            req.locale = getFilterLocale();
            req.user = req.term;
            return req;
        }
    });

    // Create the autocomplete for topic
    $('#id_topic').mozillaAutocomplete({
        minLength: 3,
        labelField: 'label',
        autocompleteUrl: '/' + currentLocale + '/dashboards/topic_lookup',
        buildRequestData: function (req) {
            // Should add locale value here
            req.locale = getFilterLocale();
            req.topic = req.term;
            return req;
        }
    });

    // Enable keynav
    $revisionReplaceBlock.mozKeyboardNav({
        itemSelector: '.dashboard-row',
        onEnterKey: function (item) {
            $(item).trigger('mdn:click');
        },
        alwaysCollectItems: true
    });

    // Focus on the first item, if there
    focusFirst();
    // Wire Show IPs button if there
    connectShowIPs();

    // Create date pickers
    $('#id_start_date, #id_end_date').datepicker();

    // When an item is clicked, load its detail
    $revisionReplaceBlock.on('click mdn:click', '.dashboard-row', function (e) {
        var $this = $(this);
        var $detail;

        // Don't interrupt links or spam buttons, and stop if a request is already running
        if (e.target.tagName === 'A' || $(e.target).hasClass('spam-ham-button') || $this.attr('data-running')) return;

        if ($this.attr('data-loaded')) {
            $this.next('.dashboard-detail').find('.dashboard-detail-details').slideToggle();
        } else {
            $this.attr('data-running', 1);
            $.ajax({
                url: $this.attr('data-compare-url')
            }).then(function (content) {
                // Prepend the controls
                var controls = controlsTemplate
                              .replace('$reverturl', $this.attr('data-revert-url'))
                              .replace('$viewurl', $this.attr('data-view-url'))
                              .replace('$editurl', $this.attr('data-edit-url'))
                              .replace('$historyurl', $this.attr('data-history-url'));

                $detail = $('<tr class="dashboard-detail"><td colspan="5"><div class="dashboard-detail-details">' + controls + content + '</div></td></tr>').insertAfter($this);
                $this.next('.dashboard-detail').find('.dashboard-detail-details').slideToggle();
                $this.attr('data-loaded', 1);
                $this.removeAttr('data-running');
            });
        }
    });

    // AJAX loads for pagination
    $revisionReplaceBlock.on('click', '.pagination a', function (e) {
        e.preventDefault();
        var pageNum = /page=([^&#]*)/.exec(this.href)[1];
        var linkText = this.text.trim();
        mdn.analytics.trackEvent({
            category: 'Dashboard Pagination',
            action: pageNum,
            label: linkText
        });
        $pageInput.val(pageNum);
        $filterForm.submit();
    });

    // Filter form submission handler; loads content via AJAX, updates URL state
    $filterForm.on('submit', function (e) {
        e.preventDefault();
        var $this = $(this);

        if ('pushState' in history) {
            history.pushState(null, '', location.pathname + '?' + $this.serialize());
        }

        var notification = mdn.Notifier.growl(gettext('Hang on! Updating filters…'), { duration: 0 });
        $.ajax({
            url: $this.attr('action'),
            data: $this.serialize()
        }).then(function (content) {
            replaceContent(content);
            $this.trigger('ajaxComplete');
            notification.success(gettext('Updated filters.'), 2000);
            // Reset the page count to 0 in case of new filter
            $pageInput.val(1);
        });
    });

    // Send revision to Akismet for Spam or Ham
    $(document).on('click', '.spam-ham-button', function() {
        var $this = $(this),
            $tdObject = $(this).parent(),
            $trObject = $tdObject.parent(),
            revisionId = $trObject.data("revisionId"),
            type = this.value,
            url = $trObject.data("spamUrl");

        $this.prop('disabled', true);
        $tdObject.find('.error , .submit').remove();
        $tdObject.append('<strong class="submit"><br>' + gettext('Submitting...') + '</strong>');

        $.post(url, {"revision": revisionId, "type": type})
          .done( function(data) {
            var $dl = $("<dl></dl>");

            $.each(data, function(index, value) {
                var subMessage = '<dt class="submission-' + value.type + '">' +
                  interpolate(gettext("Submitted as %(submission_type)s"), {submission_type: value.type}, true) + '</dt><dd>' +
                  interpolate(gettext('%(sent_date)s by %(user)s'), {sent_date: value.sent, user: value.sender}, true);

                $dl.append(subMessage);
            });

            $tdObject.html($dl);

          })
          .fail( function() {
            $this.prop('disabled', false);
            var errorMessage = '<strong class="error"><br>' + interpolate(gettext('Error submitting as %(type)s'), {type: type}, true) + '</strong>';

            $tdObject.find('.error , .submit').remove();
            $tdObject.append(errorMessage);
          });

    });

    // Wire Toggle IPs button, if present
    function connectShowIPs() {
        $('#show_ips_btn').on('click', function() {
            $('.revision_ip').slideToggle();
        });
    }

    // Returns the revision locale filter value
    function getFilterLocale() {
        return $localeInput.get(0).value || currentLocale;
    }

    // Focuses on the first row in the table
    function focusFirst() {
        var $first = $revisionReplaceBlock.find('.dashboard-row').first();
        if($first.length) {
            $first.get(0).focus();
        }
    }

    // Replaces table body content and scrolls to top of the page
    function replaceContent(content) {
        $revisionReplaceBlock.fadeOut(function () {
            $(this).html(content).fadeIn(function () {
                focusFirst();
                connectShowIPs();
            });

            // Animate to top!
            $('html, body').animate({
                scrollTop: $revisionReplaceBlock.offset().top
            }, 2000);
        });
    }

})(jQuery);
