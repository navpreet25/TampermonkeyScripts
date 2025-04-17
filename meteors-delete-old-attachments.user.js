// ==UserScript==
// @name         Meteors Delete Old Wiki Attachments
// @namespace    http://tampermonkey.net/
// @version      0.1
// @description  Delete attachments older than 2 weeks from XWiki pages
// @author       You
// @match        *://w.amazon.com/*
// @match        https://w.amazon.com/bin/view/Alexa/ACE/AlexaComms/CCX/Dashboards/Meteors*
// @match        https://w.amazon.com/bin/view/Alexa/ACE/AlexaComms/CCX/Dashboards/Meteors/*
// @run-at       document-idle
// ==/UserScript==

(function() {
    'use strict';
     console.log('Script started');// Add this line to verify script is running


    function addDeleteButton() {
        console.log('Adding delete button...');
        const button = document.createElement('button');
        button.innerHTML = 'Delete Old Attachments';
        button.style.margin = '10px';
        button.style.padding = '5px 10px';
        button.style.backgroundColor = '#f0f0f0';
        button.style.border = '1px solid #ccc';
        button.addEventListener('click', () => {
            console.log('Delete button clicked');
            deleteOldAttachments();
        });

        // Try to insert button in multiple locations
        const attachmentsSection = document.querySelector('#Attachments');
        const attachmentsList = document.querySelector('ul#_attachments');

        if (attachmentsSection) {
            attachmentsSection.insertBefore(button, attachmentsSection.firstChild);
            console.log('Button added to attachments section');
        } else if (attachmentsList) {
            attachmentsList.parentNode.insertBefore(button, attachmentsList);
            console.log('Button added before attachments list');
        } else {
            document.body.appendChild(button);
            console.log('Button added to body');
        }
    }

    // Delete attachments older than 2 weeks
    async function deleteAttachment(fileName, formToken) {
        const deleteUrl = `https://w.amazon.com/bin/delattachment/Alexa/ACE/AlexaComms/CCX/Dashboards/Meteors/WebHome/${fileName}?form_token=${formToken}&xredirect=/bin/view/Alexa/ACE/AlexaComms/CCX/Dashboards/Meteors/#Attachments`;

        try {
            const response = await fetch(deleteUrl, {
                method: 'GET',
                credentials: 'include'
            });

            if (response.ok) {
                console.log(`Successfully deleted: ${fileName}`);
                return true;
            }
        } catch (error) {
            console.error(`Failed to delete ${fileName}:`, error);
        }
        return false;
    }

    async function deleteOldAttachments() {
        const twoWeeksAgo = new Date();
        const fourWeeksAgo = new Date();
        twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);
        fourWeeksAgo.setDate(fourWeeksAgo.getDate() - 28);


        const formTokenMeta = document.querySelector('meta[name="form_token"]');
        if (!formTokenMeta) {
            console.error('Could not find form_token meta tag');
            return;
        }

        const formToken = formTokenMeta.getAttribute('content');
        console.log('Found form token:', formToken);


        const attachmentsDiv = document.querySelector('ul[id="_attachments"]');
        console.log('Attachments div found:', !!attachmentsDiv);

        const attachments = document.querySelectorAll('ul[id="_attachments"] li');

        console.log('Found attachments:', attachments.length);


        for (const attachment of attachments) {
            const dateSpan = attachment.querySelector('.date');
            console.log('Date span found:', !!dateSpan);
             if (dateSpan) {
                 const dateText = dateSpan.textContent.trim();
                 console.log('Raw date text:', dateText);
                 const cleanDateText = dateText.replace(' on ', '').replace(' UTC', '');
                 const attachmentDate = new Date(cleanDateText);
                 if (attachmentDate >= fourWeeksAgo && attachmentDate <= twoWeeksAgo) {
                     const fileName = attachment.querySelector('a').textContent;
                     console.log('Processing attachment:', fileName, 'from date:', attachmentDate);
                     await deleteAttachment(fileName, formToken);
                     await new Promise(resolve => setTimeout(resolve, 500));
                 }
             }
        }
    }

    // Modified initialization
    window.addEventListener('load', function() {
        console.log('Window loaded');
        setTimeout(() => {
            console.log('Attempting to add button...');
            addDeleteButton();
        }, 2000);
    });
})();

