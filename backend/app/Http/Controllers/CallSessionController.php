<?php

namespace App\Http\Controllers;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class CallSessionController
{
    public function __invoke(Request $request): JsonResponse
    {
        $baseUrl = rtrim((string) config('services.blendlix_call.base_url'), '/');
        $keyId = (string) config('services.blendlix_call.product_key_id');
        $secret = (string) config('services.blendlix_call.product_secret');

        if ($baseUrl === '' || $keyId === '' || $secret === '') {
            return response()->json(['message' => 'Call service is not configured.'], 503);
        }

        $contextType = 'application';
        $contextId = (string) config('services.blendlix_call.context_id', 'dialbase-global');
        $payload = [
            'context_type' => $contextType,
            'context_id' => $contextId,
            'user_id' => (string) $request->user()->getKey(),
            'role' => 'user',
            'display_name' => $request->user()->name,
            'allowed_peer_role' => 'user',
        ];

        try {
            $serviceResponse = Http::acceptJson()
                ->asJson()
                ->withHeaders([
                    'X-Dialbase-Key-ID' => $keyId,
                    'X-Dialbase-Secret' => $secret,
                ])
                ->timeout(15)
                ->post($baseUrl.'/v1/call/session-token', $payload);
        } catch (ConnectionException $exception) {
            Log::warning('Blendlix call service connection failed.', ['message' => $exception->getMessage()]);

            return response()->json(['message' => 'Call service is unavailable.'], 502);
        }

        if (! $serviceResponse->successful()) {
            Log::warning('Blendlix call service rejected a session request.', ['status' => $serviceResponse->status()]);

            $message = match ($serviceResponse->status()) {
                401 => 'Call service rejected the product credentials. Check the key ID and secret in your environment.',
                403 => 'Call service rejected this project credential or the project is inactive.',
                default => 'Could not start a call session.',
            };

            return response()->json(['message' => $message], 502);
        }

        $session = $serviceResponse->json();

        if (! is_array($session) || ! isset($session['token'], $session['ws_url']) || ! is_array($session['ice_servers'] ?? null)) {
            Log::warning('Blendlix call service returned an invalid session response.');

            return response()->json(['message' => 'Call service returned an invalid response.'], 502);
        }

        return response()->json([
            'token' => $session['token'],
            'expires_at' => $session['expires_at'] ?? null,
            'ws_url' => $session['ws_url'],
            'ice_servers' => $session['ice_servers'],
            'context_type' => $contextType,
            'context_id' => $contextId,
            'user_id' => (string) $request->user()->getKey(),
            'role' => 'user',
        ]);
    }
}
