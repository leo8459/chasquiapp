<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'siop_tracking_events' => [
        'url' => env('SIOP_TRACKING_EVENTS_URL', 'https://trackingbo.correos.gob.bo:8100/api/siop/eventos'),
        'token' => env('SIOP_TRACKING_EVENTS_TOKEN'),
        'timeout' => (int) env('SIOP_TRACKING_EVENTS_TIMEOUT', 12),
        'verify_ssl' => (bool) env('SIOP_TRACKING_EVENTS_VERIFY_SSL', true),
    ],

];
