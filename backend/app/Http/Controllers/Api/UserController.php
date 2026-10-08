<?php

namespace App\Http\Controllers\Api;

use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class UserController
{
    public function __invoke(Request $request): JsonResponse
    {
        $data = $request->validate([
            'search' => ['sometimes', 'string', 'max:100'],
            'per_page' => ['sometimes', 'integer', 'between:1,100'],
        ]);

        $users = User::query()
            ->select(['id', 'name'])
            ->whereKeyNot($request->user()->getKey())
            ->whereNotNull('email_verified_at')
            ->when($data['search'] ?? null, fn ($query, $search) => $query->where('name', 'like', '%'.$search.'%'))
            ->orderBy('name')
            ->orderBy('id')
            ->paginate($data['per_page'] ?? 25);

        return response()->json($users);
    }
}
