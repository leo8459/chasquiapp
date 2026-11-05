<?php

return [
    // Debe coincidir con version en pubspec.yaml, incluido el build (+N).
    'required_version' => env('MOBILE_REQUIRED_VERSION', '1.0.5+6'),
    'download_url' => env('MOBILE_DOWNLOAD_URL', ''),
];
