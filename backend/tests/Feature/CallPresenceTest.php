<?php

use App\Models\User;

test('authenticated users can join the calls presence channel', function () {
    $user = User::factory()->create(['name' => 'Amina']);

    $response = $this->actingAs($user, 'web')->postJson('/broadcasting/auth', [
        'socket_id' => '1234.5678',
        'channel_name' => 'presence-calls',
    ]);

    expect($response->status())->toBe(200, 'Broadcast auth response: '.$response->getContent());

    $channelData = json_decode($response->json('channel_data'), true, flags: JSON_THROW_ON_ERROR);

    expect($channelData['user_info'])->toMatchArray([
        'id' => (string) $user->id,
        'name' => 'Amina',
    ]);
});

test('guests cannot join the calls presence channel', function () {
    $response = $this->postJson('/broadcasting/auth', [
        'socket_id' => '1234.5678',
        'channel_name' => 'presence-calls',
    ]);

    $response->assertUnauthorized();
});
