<?php

use App\Models\User;

test('guests are redirected to the login page', function () {
    $response = $this->get(route('dashboard'));
    $response->assertRedirect(route('login'));
});

test('authenticated users without a verified email are redirected to verification', function () {
    $user = User::factory()->create(['email_verified_at' => null]);
    $this->actingAs($user);

    $response = $this->get(route('dashboard'));
    $response->assertRedirect(route('verification.notice'));
});

test('verified users can visit the dashboard', function () {
    $user = User::factory()->create();
    $this->actingAs($user);

    $this->get(route('dashboard'))
        ->assertOk()
        ->assertSee('aria-labelledby="call-window-title"', false)
        ->assertSee('data-call-accept', false)
        ->assertSee('data-call-mute', false)
        ->assertSee('data-call-duration', false)
        ->assertSee('data-call-restore', false);
});

test('dashboard lists other registered users with a call button for each', function () {
    $user = User::factory()->create(['name' => 'Natala']);
    User::factory()->create(['name' => 'Amina']);
    $this->actingAs($user);

    $response = $this->get(route('dashboard'));

    $response->assertOk()
        ->assertSeeText('Call');

    $content = $response->getContent();

    expect(str_contains($content, 'aria-label="Call Amina"'))->toBeTrue()
        ->and(str_contains($content, 'aria-label="Call Natala"'))->toBeFalse()
        ->and(substr_count($content, 'aria-label="Call '))->toBe(1);
});
