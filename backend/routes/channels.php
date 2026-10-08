<?php

use App\Models\User;
use Illuminate\Support\Facades\Broadcast;

Broadcast::channel('App.Models.User.{id}', function ($user, $id) {
    return (int) $user->id === (int) $id;
});

Broadcast::channel('calls', function (User $user): array {
    return [
        'id' => (string) $user->getKey(),
        'name' => $user->name,
    ];
}, ['guards' => ['web', 'sanctum']]);
