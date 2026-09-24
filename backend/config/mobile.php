<?php

return [
    'minimum_version' => env('MOBILE_MINIMUM_VERSION', '1.0.0'),
    'download_url' => env('MOBILE_DOWNLOAD_URL')
        ?: rtrim((string) env('APP_URL', 'http://localhost'), '/')
            .'/descargas/chasquiapp.apk',
];
