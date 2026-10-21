<?php
// Neutral target page. The bug is in PHP core's request-startup path, so the
// application code here is irrelevant: the trigger fires before RINIT.
header('X-Lab: php2shell');
echo "php2shell lab target\n";
echo "PHP ", PHP_VERSION, " ", PHP_SAPI, "\n";
echo "upload_progress=", ini_get('session.upload_progress.enabled'), "\n";
