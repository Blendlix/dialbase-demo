<?php

namespace App\Http\Controllers\Api;

use Illuminate\Http\JsonResponse;

class CallConfigController
{
    public function __invoke(): JsonResponse
    {
        $connection = config('broadcasting.connections.reverb');
        $options = $connection['options'];

        // The app key is public; the Reverb secret must never be sent to clients.
        return response()->json(['data' => [
            'key' => $connection['key'],
            'host' => $options['host'],
            'port' => (int) $options['port'],
            'scheme' => $options['scheme'] === 'https' ? 'wss' : 'ws',
        ]]);
    }
}
