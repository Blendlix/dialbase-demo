<?php

use App\Models\User;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Support\Facades\Http;

test('authenticated users receive a call session token from the call service', function () {
    $user = User::factory()->create(['name' => 'Natala']);
    config([
        'services.blendlix_call.base_url' => 'https://rtc.example.test',
        'services.blendlix_call.product_key_id' => 'test-key-id',
        'services.blendlix_call.product_secret' => 'test-secret',
        'services.blendlix_call.product' => 'stale-product-slug',
        'services.blendlix_call.context_id' => 'dialbase-test',
    ]);

    Http::fake([
        'rtc.example.test/v1/call/session-token' => Http::response([
            'token' => 'session-token',
            'expires_at' => '2026-10-07T12:15:00Z',
            'ws_url' => 'wss://rtc.example.test/v1/ws',
            'ice_servers' => [['urls' => ['stun:rtc.example.test:3478']]],
        ]),
    ]);

    $response = $this->actingAs($user)->postJson(route('calls.session'));

    $response->assertOk()
        ->assertJsonPath('token', 'session-token')
        ->assertJsonPath('expires_at', '2026-10-07T12:15:00Z')
        ->assertJsonPath('user_id', (string) $user->id)
        ->assertJsonPath('context_id', 'dialbase-test');

    Http::assertSent(fn (HttpRequest $request) => $request->url() === 'https://rtc.example.test/v1/call/session-token'
        && $request->hasHeader('X-Dialbase-Key-ID', 'test-key-id')
        && $request->hasHeader('X-Dialbase-Secret', 'test-secret')
        && $request['user_id'] === (string) $user->id
        && $request['role'] === 'user'
        && $request['allowed_peer_role'] === 'user'
        && $request['context_id'] === 'dialbase-test'
        && ! isset($request['product'])
    );
});

test('guests cannot request a call session', function () {
    $this->postJson(route('calls.session'))->assertUnauthorized();
});

test('call session responses explain rejected product credentials', function () {
    $user = User::factory()->create();
    config([
        'services.blendlix_call.base_url' => 'https://rtc.example.test',
        'services.blendlix_call.product_key_id' => 'test-key-id',
        'services.blendlix_call.product_secret' => 'test-secret',
    ]);

    Http::fake([
        'rtc.example.test/v1/call/session-token' => Http::response([
            'error' => ['code' => 'PRODUCT_AUTH_INVALID_SECRET'],
        ], 401),
    ]);

    $this->actingAs($user)
        ->postJson(route('calls.session'))
        ->assertStatus(502)
        ->assertJsonPath('message', 'Call service rejected the product credentials. Check the key ID and secret in your environment.');
});

test('call session responses explain rejected project credentials', function () {
    $user = User::factory()->create();
    config([
        'services.blendlix_call.base_url' => 'https://rtc.example.test',
        'services.blendlix_call.product_key_id' => 'test-key-id',
        'services.blendlix_call.product_secret' => 'test-secret',
    ]);

    Http::fake([
        'rtc.example.test/v1/call/session-token' => Http::response([
            'error' => ['code' => 'PRODUCT_AUTH_PRODUCT_MISMATCH'],
        ], 403),
    ]);

    $this->actingAs($user)
        ->postJson(route('calls.session'))
        ->assertStatus(502)
        ->assertJsonPath('message', 'Call service rejected this project credential or the project is inactive.');
});

test('call session requests fail safely when credentials are missing', function () {
    $user = User::factory()->create();
    config([
        'services.blendlix_call.product_key_id' => null,
        'services.blendlix_call.product_secret' => null,
    ]);

    $this->actingAs($user)
        ->postJson(route('calls.session'))
        ->assertServiceUnavailable()
        ->assertJsonPath('message', 'Call service is not configured.');
});
