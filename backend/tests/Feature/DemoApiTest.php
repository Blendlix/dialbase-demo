<?php

use App\Models\CallHistory;
use App\Models\User;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Auth\Notifications\VerifyEmail;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;

function demoApiToken(User $user): string
{
    return $user->createToken('test-client', ['*'], now()->addDay())->plainTextToken;
}

test('api registration uses the existing password rules and sends verification', function () {
    Notification::fake();
    $response = $this->postJson('/api/v1/auth/register', [
        'name' => 'Amina', 'email' => 'amina@example.test',
        'password' => 'password123', 'password_confirmation' => 'password123', 'device_name' => 'mobile',
    ]);
    $response->assertCreated()->assertJsonPath('token_type', 'Bearer')->assertJsonPath('user.email_verified_at', null);
    $user = User::query()->where('email', 'amina@example.test')->firstOrFail();
    Notification::assertSentTo($user, VerifyEmail::class);
    $this->withToken($response->json('access_token'))->getJson('/api/v1/me')->assertOk()->assertJsonPath('data.id', $user->id);
    $this->getJson('/api/v1/users')->assertForbidden();
});

test('api login rejects wrong passwords and two factor accounts', function () {
    $user = User::factory()->create();
    $payload = ['email' => $user->email, 'password' => 'wrong', 'device_name' => 'test'];
    $this->postJson('/api/v1/auth/login', $payload)->assertUnprocessable();
    $user->forceFill(['two_factor_secret' => encrypt('secret')])->save();
    $payload['password'] = 'password';
    $this->postJson('/api/v1/auth/login', $payload)->assertUnprocessable();
    expect($user->tokens()->count())->toBe(0);
});

test('api login returns an expiring token and logout revokes only that token', function () {
    $user = User::factory()->create();
    $otherToken = $user->createToken('other-device')->accessToken;
    $response = $this->postJson('/api/v1/auth/login', ['email' => $user->email, 'password' => 'password', 'device_name' => 'test']);
    $response->assertOk()->assertJsonStructure(['access_token', 'expires_at', 'user']);
    $this->withToken($response->json('access_token'))->postJson('/api/v1/auth/logout')->assertNoContent();
    expect($user->tokens()->count())->toBe(1);
    expect($user->tokens()->first()->id)->toBe($otherToken->id);
});

test('api rejects missing expired and revoked bearer tokens', function () {
    $this->getJson('/api/v1/me')->assertUnauthorized();
    $user = User::factory()->create();
    $expired = $user->createToken('expired', ['*'], now()->subMinute());
    $this->withToken($expired->plainTextToken)->getJson('/api/v1/me')->assertUnauthorized();
    $revoked = $user->createToken('revoked');
    $revoked->accessToken->delete();
    $this->withToken($revoked->plainTextToken)->getJson('/api/v1/me')->assertUnauthorized();
});

test('api directory is paginated and exposes only callable user identities', function () {
    $user = User::factory()->create();
    $peer = User::factory()->create(['name' => 'Amina']);
    User::factory()->create(['name' => 'Unverified', 'email_verified_at' => null]);
    $this->withToken(demoApiToken($user))->getJson('/api/v1/users?search=Amina&per_page=1')
        ->assertOk()->assertJsonPath('total', 1)->assertJsonPath('data.0.id', $peer->id)->assertJsonMissingPath('data.0.email');
    $this->getJson('/api/v1/users?per_page=1000')->assertUnprocessable();
});

test('api sessions derive identity server side and keep credentials private', function () {
    $user = User::factory()->create();
    config(['services.blendlix_call.base_url' => 'https://rtc.example.test', 'services.blendlix_call.product_key_id' => 'key', 'services.blendlix_call.product_secret' => 'secret']);
    Http::fake(['rtc.example.test/*' => Http::response(['token' => 'rtc-token', 'expires_at' => now()->addMinutes(15)->toISOString(), 'ws_url' => 'wss://rtc.example.test/v1/ws', 'ice_servers' => []])]);
    $this->withToken(demoApiToken($user))->postJson('/api/v1/calls/session', ['user_id' => 'someone-else', 'role' => 'admin'])
        ->assertOk()->assertJsonPath('user_id', (string) $user->id)->assertJsonPath('role', 'user')->assertJsonMissingPath('secret');
    Http::assertSent(fn ($request) => $request['user_id'] === (string) $user->id && $request['role'] === 'user');
});

test('unverified api users cannot request call sessions', function () {
    Http::fake();
    $user = User::factory()->create(['email_verified_at' => null]);
    $this->withToken(demoApiToken($user))->postJson('/api/v1/calls/session')->assertForbidden();
    Http::assertNothingSent();
});

test('api history remains isolated to the authenticated user', function () {
    $user = User::factory()->create();
    $peer = User::factory()->create();
    $this->withToken(demoApiToken($user))->postJson('/api/v1/calls/history', ['peer_user_id' => $peer->id, 'direction' => 'outgoing'])->assertCreated();
    $history = CallHistory::query()->firstOrFail();
    $this->getJson('/api/v1/calls/history')->assertOk()->assertJsonCount(1, 'data');
    app('auth')->forgetGuards();
    $this->withToken(demoApiToken($peer))->patchJson('/api/v1/calls/history/'.$history->id, ['status' => 'ended'])->assertNotFound();
});

test('api clients can authorize the shared Reverb presence channel', function () {
    $user = User::factory()->create();
    $this->withToken(demoApiToken($user))->postJson('/api/v1/broadcasting/auth', ['socket_id' => '1234.5678', 'channel_name' => 'presence-calls'])
        ->assertOk()->assertJsonStructure(['auth', 'channel_data']);
});

test('api login is rate limited', function () {
    $payload = ['email' => 'missing@example.test', 'password' => 'wrong', 'device_name' => 'test'];
    for ($attempt = 0; $attempt < 5; $attempt++) {
        $this->postJson('/api/v1/auth/login', $payload)->assertUnprocessable();
    }
    $this->postJson('/api/v1/auth/login', $payload)->assertTooManyRequests();
});

test('mobile clients receive only public Reverb connection settings', function () {
    $user = User::factory()->create();
    config(['broadcasting.connections.reverb.key' => 'public-key', 'broadcasting.connections.reverb.secret' => 'private-secret']);
    $this->withToken(demoApiToken($user))->getJson('/api/v1/calls/config')
        ->assertOk()->assertJsonPath('data.key', 'public-key')
        ->assertJsonMissingPath('data.secret')->assertDontSee('private-secret');
});

test('api password reset sends the existing reset notification without exposing accounts', function () {
    Notification::fake();
    $user = User::factory()->create();
    $known = $this->postJson('/api/v1/auth/forgot-password', ['email' => $user->email])->assertOk();
    Notification::assertSentTo($user, ResetPassword::class);
    $this->postJson('/api/v1/auth/forgot-password', ['email' => 'missing@example.test'])
        ->assertOk()->assertExactJson($known->json());
});
