<?php

return [
    'minimum_version' => env('MOBILE_MINIMUM_VERSION', '1.0.0'),
    'download_url' => env(
        'MOBILE_DOWNLOAD_URL',
        'https://dev.correos.gob.bo:18100/chasquiapp/descargas/chasquiapp.apk',
    ),
];
