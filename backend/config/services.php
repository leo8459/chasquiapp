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
        'url' => env('SIOP_TRACKING_EVENTS_URL', 'https://dev.correos.gob.bo:18100/api/paquetes-eventos'),
        'token' => env('SIOP_TRACKING_EVENTS_TOKEN'),
        'timeout' => (int) env('SIOP_TRACKING_EVENTS_TIMEOUT', 12),
        'verify_ssl' => (bool) env('SIOP_TRACKING_EVENTS_VERIFY_SSL', true),
    ],

    'siop_login' => [
        'url' => env('SIOP_LOGIN_URL', 'https://dev.correos.gob.bo:18100/api/integraciones/siop/login'),
        'token' => env('SIOP_LOGIN_TOKEN'),
        'timeout' => (int) env('SIOP_LOGIN_TIMEOUT', 15),
        'verify_ssl' => (bool) env('SIOP_LOGIN_VERIFY_SSL', true),
    ],

    'siop_courier_packages' => [
        'assigned_url' => env('SIOP_COURIER_ASSIGNED_URL', 'https://dev.correos.gob.bo:18100/api/chasqui/paquetes-asignados'),
        'assigned_token' => env('SIOP_COURIER_ASSIGNED_TOKEN'),
        'assign_url' => env('SIOP_COURIER_ASSIGN_URL', 'https://dev.correos.gob.bo:18100/api/chasqui/paquetes/asignar'),
        'assign_token' => env('SIOP_COURIER_ASSIGN_TOKEN'),
        'deliver_url' => env('SIOP_COURIER_DELIVER_URL', 'https://dev.correos.gob.bo:18100/api/chasqui/paquetes/entregar'),
        'deliver_token' => env('SIOP_COURIER_DELIVER_TOKEN'),
        'deliver_timeout' => (int) env('SIOP_COURIER_DELIVER_TIMEOUT', 60),
        'timeout' => (int) env('SIOP_COURIER_PACKAGES_TIMEOUT', 20),
        'verify_ssl' => (bool) env('SIOP_COURIER_PACKAGES_VERIFY_SSL', true),
    ],

    'siop_courier_notifications' => [
        'pending_url' => env('SIOP_COURIER_NOTIFICATIONS_PENDING_URL', 'https://dev.correos.gob.bo:18100/api/chasqui/notificaciones/pendientes'),
        'token' => env('SIOP_COURIER_NOTIFICATIONS_TOKEN'),
        'timeout' => (int) env('SIOP_COURIER_NOTIFICATIONS_TIMEOUT', 20),
        'verify_ssl' => (bool) env('SIOP_COURIER_NOTIFICATIONS_VERIFY_SSL', true),
    ],

];
