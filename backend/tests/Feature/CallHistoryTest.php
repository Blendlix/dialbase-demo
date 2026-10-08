<?php

use App\Models\CallHistory;
use App\Models\User;
use Illuminate\Support\Carbon;

test('users can record incoming and outgoing calls in their own history', function () {
    $user = User::factory()->create();
    $peer = User::factory()->create(['name' => 'Amina']);
    $this->actingAs($user);

    $outgoing = $this->postJson(route('calls.history.store'), [
        'peer_user_id' => $peer->id,
        'direction' => 'outgoing',
    ]);

    $outgoing->assertCreated()
        ->assertJsonPath('data.direction', 'outgoing')
        ->assertJsonPath('data.status', 'initiated')
        ->assertJsonPath('data.peer_name', 'Amina');

    $incoming = $this->postJson(route('calls.history.store'), [
        'peer_user_id' => $peer->id,
        'direction' => 'incoming',
        'call_uuid' => '78927945-9ff0-4863-89ab-c08cbefed134',
    ]);

    $incoming->assertCreated()
        ->assertJsonPath('data.direction', 'incoming')
        ->assertJsonPath('data.status', 'ringing');

    expect(CallHistory::query()->where('user_id', $user->id)->count())->toBe(2);
});

test('call history status updates calculate connected duration and keep unconnected calls at zero', function () {
    $user = User::factory()->create();
    $peer = User::factory()->create();
    $this->actingAs($user);

    Carbon::setTestNow('2026-09-26 10:00:00');
    $history = CallHistory::query()->create([
        'user_id' => $user->id,
        'peer_user_id' => $peer->id,
        'direction' => 'outgoing',
        'status' => 'initiated',
        'initiated_at' => now(),
    ]);

    Carbon::setTestNow('2026-09-26 10:01:00');
    $this->patchJson(route('calls.history.update', $history), [
        'status' => 'connected',
        'call_uuid' => '78927945-9ff0-4863-89ab-c08cbefed134',
    ])->assertOk()
        ->assertJsonPath('data.status', 'connected')
        ->assertJsonPath('data.duration_seconds', 0);

    Carbon::setTestNow('2026-09-26 10:04:12');
    $this->patchJson(route('calls.history.update', $history), [
        'status' => 'ended',
    ])->assertOk()
        ->assertJsonPath('data.status', 'ended')
        ->assertJsonPath('data.duration_seconds', 192);

    $unanswered = CallHistory::query()->create([
        'user_id' => $user->id,
        'peer_user_id' => $peer->id,
        'direction' => 'incoming',
        'status' => 'ringing',
        'initiated_at' => now(),
    ]);

    $this->patchJson(route('calls.history.update', $unanswered), [
        'status' => 'canceled',
    ])->assertOk()->assertJsonPath('data.duration_seconds', 0);

    Carbon::setTestNow();
});

test('users cannot read or update another users call history', function () {
    $owner = User::factory()->create();
    $other = User::factory()->create();
    $peer = User::factory()->create();
    $history = CallHistory::query()->create([
        'user_id' => $owner->id,
        'peer_user_id' => $peer->id,
        'direction' => 'outgoing',
        'status' => 'ringing',
        'initiated_at' => now(),
    ]);

    $this->actingAs($other)
        ->getJson(route('calls.history.index'))
        ->assertOk()
        ->assertJsonCount(0, 'data');

    $this->patchJson(route('calls.history.update', $history), [
        'status' => 'connected',
    ])->assertNotFound();
});

test('guests cannot access call history', function () {
    $this->getJson(route('calls.history.index'))->assertUnauthorized();
});
