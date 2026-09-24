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
        'url' => env('SIOP_TRACKING_EVENTS_URL'),
        'token' => env('SIOP_TRACKING_EVENTS_TOKEN'),
        'timeout' => (int) env('SIOP_TRACKING_EVENTS_TIMEOUT', 30),
        'verify_ssl' => (bool) env('SIOP_TRACKING_EVENTS_VERIFY_SSL', true),
    ],

    'siop_bitacoras' => [
        'url' => env('SIOP_BITACORA_URL'),
        'read_token' => env('SIOP_BITACORA_TOKEN'),
        'create_token' => env('SIOP_BITACORA_CREATE_TOKEN'),
        'timeout' => (int) env('SIOP_BITACORA_TIMEOUT', 30),
        'verify_ssl' => (bool) env('SIOP_BITACORA_VERIFY_SSL', true),
    ],

    'siop_gasolinas' => [
        'url' => env('SIOP_GASOLINA_URL'),
        'read_token' => env('SIOP_GASOLINA_TOKEN'),
        'create_token' => env('SIOP_GASOLINA_CREATE_TOKEN'),
        'timeout' => (int) env('SIOP_GASOLINA_TIMEOUT', 30),
        'verify_ssl' => (bool) env('SIOP_GASOLINA_VERIFY_SSL', true),
    ],

    'siop_mantenimientos' => [
        'url' => env('SIOP_MANTENIMIENTO_URL'),
        'token' => env('SIOP_MANTENIMIENTO_TOKEN'),
        'timeout' => (int) env('SIOP_MANTENIMIENTO_TIMEOUT', 30),
        'verify_ssl' => (bool) env('SIOP_MANTENIMIENTO_VERIFY_SSL', true),
    ],

    'siop_login' => [
        'url' => env('SIOP_LOGIN_URL'),
        'token' => env('SIOP_LOGIN_TOKEN'),
        'timeout' => (int) env('SIOP_LOGIN_TIMEOUT', 30),
        'verify_ssl' => (bool) env('SIOP_LOGIN_VERIFY_SSL', true),
    ],

    'siop_courier_packages' => [
        'assigned_url' => env('SIOP_COURIER_ASSIGNED_URL'),
        'assigned_token' => env('SIOP_COURIER_ASSIGNED_TOKEN'),
        'assign_url' => env('SIOP_COURIER_ASSIGN_URL'),
        'assign_token' => env('SIOP_COURIER_ASSIGN_TOKEN'),
        'deliver_url' => env('SIOP_COURIER_DELIVER_URL'),
        'deliver_token' => env('SIOP_COURIER_DELIVER_TOKEN'),
        'contract_pickup_url' => env('SIOP_CONTRACT_PICKUP_URL'),
        'contract_pickup_token' => env('SIOP_CONTRACT_PICKUP_TOKEN'),
        'deliver_timeout' => (int) env('SIOP_COURIER_DELIVER_TIMEOUT', 30),
        'timeout' => (int) env('SIOP_COURIER_PACKAGES_TIMEOUT', 30),
        'verify_ssl' => (bool) env('SIOP_COURIER_PACKAGES_VERIFY_SSL', true),
    ],

    'siop_courier_notifications' => [
        'pending_url' => env('SIOP_COURIER_NOTIFICATIONS_PENDING_URL'),
        'token' => env('SIOP_COURIER_NOTIFICATIONS_TOKEN'),
        'timeout' => (int) env('SIOP_COURIER_NOTIFICATIONS_TIMEOUT', 30),
        'verify_ssl' => (bool) env('SIOP_COURIER_NOTIFICATIONS_VERIFY_SSL', true),
    ],

    'siop_courier_location' => [
        'url' => env('SIOP_COURIER_LOCATION_URL'),
        'token' => env('SIOP_COURIER_LOCATION_TOKEN'),
        'timeout' => (int) env('SIOP_COURIER_LOCATION_TIMEOUT', 30),
        'verify_ssl' => (bool) env('SIOP_COURIER_LOCATION_VERIFY_SSL', true),
    ],

];
