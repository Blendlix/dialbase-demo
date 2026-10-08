<?php

namespace App\Http\Controllers\Api;

use App\Actions\Fortify\CreateNewUser;
use App\Models\User;
use Illuminate\Auth\Events\Registered;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\PersonalAccessToken;

class AuthController
{
    public function forgotPassword(Request $request): JsonResponse
    {
        $data = $request->validate(['email' => ['required', 'string', 'email']]);
        Password::sendResetLink($data);

        return response()->json(['message' => 'If this account exists, a password reset link has been sent.']);
    }

    public function register(Request $request, CreateNewUser $createUser): JsonResponse
    {
        $request->validate(['device_name' => ['required', 'string', 'max:100']]);
        $user = $createUser->create($request->only(['name', 'email', 'password', 'password_confirmation']));
        event(new Registered($user));

        return $this->tokenResponse($user, $request->string('device_name')->toString(), 201);
    }

    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'string', 'email'],
            'password' => ['required', 'string'],
            'device_name' => ['required', 'string', 'max:100'],
        ]);
        $user = User::query()->where('email', $data['email'])->first();

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages(['email' => 'The provided credentials are incorrect.']);
        }

        // Password-only API login must not bypass the existing two-factor flow.
        if ($user->two_factor_secret !== null) {
            throw ValidationException::withMessages(['email' => 'Accounts with two-factor authentication must use the web sign-in flow.']);
        }

        return $this->tokenResponse($user, $data['device_name']);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json(['data' => $request->user()->only(['id', 'name', 'email', 'email_verified_at'])]);
    }

    public function logout(Request $request): Response
    {
        $token = $request->user()->currentAccessToken();
        if ($token instanceof PersonalAccessToken) {
            $token->delete();
        }

        return response()->noContent();
    }

    public function verificationNotification(Request $request): JsonResponse
    {
        if (! $request->user()->hasVerifiedEmail()) {
            $request->user()->sendEmailVerificationNotification();
        }

        return response()->json(['message' => 'Verification email sent if verification is still required.']);
    }

    private function tokenResponse(User $user, string $deviceName, int $status = 200): JsonResponse
    {
        $expiresAt = now()->addDay();
        $token = $user->createToken($deviceName, ['*'], $expiresAt);

        return response()->json([
            'token_type' => 'Bearer',
            'access_token' => $token->plainTextToken,
            'expires_at' => $expiresAt->toISOString(),
            'user' => $user->only(['id', 'name', 'email', 'email_verified_at']),
        ], $status);
    }
}
